import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SignJWT, importPKCS8 } from "https://deno.land/x/jose@v5.9.6/index.ts";

const TIME_ZONE = "America/Guayaquil";
const PROJECT_ID = Deno.env.get("FIREBASE_PROJECT_ID") ?? "";

type Notice = "three_days" | "one_day";
type ServiceAccount = { client_email: string; private_key: string };

export function guayaquilDate(now = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: TIME_ZONE, year: "numeric", month: "2-digit", day: "2-digit" }).format(now);
}

export function addDays(date: string, days: number): string {
  const value = new Date(`${date}T12:00:00Z`);
  value.setUTCDate(value.getUTCDate() + days);
  return value.toISOString().slice(0, 10);
}

async function accessToken(account: ServiceAccount): Promise<string> {
  const key = await importPKCS8(account.private_key, "RS256");
  const now = Math.floor(Date.now() / 1000);
  const assertion = await new SignJWT({ scope: "https://www.googleapis.com/auth/firebase.messaging" })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" }).setIssuer(account.client_email)
    .setSubject(account.client_email).setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(now).setExpirationTime(now + 3600).sign(key);
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  if (!response.ok) throw new Error(`oauth_${response.status}`);
  return (await response.json()).access_token;
}

function content(notice: Notice) {
  return notice === "three_days"
    ? { title: "Próximo pago", body: "Tienes un pago programado dentro de 3 días." }
    : { title: "Pago programado para mañana", body: "Recuerda revisar el pago pendiente." };
}

function permanentFcmError(code: string) {
  return ["UNREGISTERED", "INVALID_ARGUMENT", "SENDER_ID_MISMATCH"].some((value) => code.includes(value));
}

Deno.serve(async (request) => {
  const expected = Deno.env.get("CRON_SECRET") ?? "";
  if (!expected || request.headers.get("authorization") !== `Bearer ${expected}`) return new Response("Unauthorized", { status: 401 });
  const url = Deno.env.get("SUPABASE_URL")!;
  const role = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const rawAccount = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON") ?? "";
  if (!url || !role || !PROJECT_ID || !rawAccount) return Response.json({ error: "missing_server_configuration" }, { status: 500 });
  const db = createClient(url, role, { auth: { persistSession: false } });
  const account = JSON.parse(rawAccount) as ServiceAccount;
  const token = await accessToken(account);
  const today = guayaquilDate();
  const summary = { reminders: 0, sent: 0, temporaryFailures: 0, permanentFailures: 0, noDevices: 0, skipped: 0 };

  for (const [notice, offset, flag] of [["three_days", 3, "notify_three_days"], ["one_day", 1, "notify_one_day"]] as const) {
    const due = addDays(today, offset);
    const { data: reminders, error } = await db.from("payment_reminders").select("id,user_id,factura_id,schedule_version,payment_date").eq("active", true).eq(flag, true).eq("payment_date", due);
    if (error) throw error;
    for (const reminder of reminders ?? []) {
      summary.reminders++;
      const { data: devices } = await db.from("fcm_devices").select("id,token").eq("user_id", reminder.user_id).eq("active", true);
      if (!devices?.length) {
        await db.from("payment_notification_events").insert({ reminder_id: reminder.id, schedule_version: reminder.schedule_version, device_id: null, notice_type: notice, scheduled_for: due, status: "no_devices" });
        summary.noDevices++;
        continue;
      }
      for (const device of devices) {
        const { data: claims, error: claimError } = await db.rpc("claim_payment_notification_event", { p_reminder_id: reminder.id, p_schedule_version: reminder.schedule_version, p_device_id: device.id, p_notice_type: notice, p_scheduled_for: due });
        const event = claims?.[0];
        if (claimError || !event) { summary.skipped++; continue; }
        const visible = content(notice as Notice);
        const response = await fetch(`https://fcm.googleapis.com/v1/projects/${PROJECT_ID}/messages:send`, { method: "POST", headers: { authorization: `Bearer ${token}`, "content-type": "application/json" }, body: JSON.stringify({ message: { token: device.token, notification: visible, data: { type: "recordatorio_pago", factura_id: reminder.factura_id, recordatorio_id: reminder.id }, android: { priority: "high", notification: { channel_id: "recordatorios_pago" } } } }) });
        const result = await response.json().catch(() => ({}));
        if (response.ok) {
          await db.from("payment_notification_events").update({ status: "sent", attempt_count: (event.attempt_count ?? 0) + 1, fcm_message_id: result.name ?? null, sent_at: new Date().toISOString(), last_error_code: null }).eq("id", event.event_id); summary.sent++;
        } else {
          const fcmDetail = result?.error?.details?.find?.((detail: Record<string, unknown>) => String(detail["@type"] ?? "").includes("FcmError"));
          const code = String(fcmDetail?.errorCode ?? result?.error?.status ?? `HTTP_${response.status}`);
          const permanent = permanentFcmError(code);
          await db.from("payment_notification_events").update({ status: permanent ? "permanent_failure" : "temporary_failure", attempt_count: (event.attempt_count ?? 0) + 1, last_error_code: code.slice(0, 120), next_retry_at: permanent ? null : new Date(Date.now() + 30 * 60_000).toISOString() }).eq("id", event.event_id);
          if (permanent) { await db.from("fcm_devices").update({ active: false, updated_at: new Date().toISOString() }).eq("id", device.id); summary.permanentFailures++; } else summary.temporaryFailures++;
        }
      }
    }
  }
  return Response.json(summary);
});
