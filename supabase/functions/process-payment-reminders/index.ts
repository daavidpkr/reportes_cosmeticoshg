import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { importPKCS8, SignJWT } from "jose";

import {
  buildFcmPayload,
  classifyFcmError,
  classifyThrownError,
  DEVICE_CONCURRENCY,
  dueDateForNotice,
  emptySummary,
  filterEnterpriseDevices,
  finalDeliveryBlockReason,
  guayaquilDate,
  mapLimit,
  MAX_ATTEMPTS,
  nextRetryAt,
  type Notice,
  type OperationalSummary,
  PAGE_SIZE,
  parseOAuthResponse,
  processingRecoveryCutoff,
  requireDeviceQuery,
  retryBlockReason,
  type RuntimeConfig,
  type ServiceAccount,
  validateRuntimeConfig,
} from "./core.ts";

type Reminder = {
  id: string;
  user_id: string;
  organization_id: string;
  factura_id: string;
  schedule_version: string;
  payment_date: string;
  active?: boolean;
  notify_three_days?: boolean;
  notify_one_day?: boolean;
};

type Device = {
  id: string;
  user_id?: string;
  organization_id?: string;
  token: string;
  active?: boolean;
};
type ClaimedEvent = { event_id: string; attempt_count: number };
type RetryEvent = {
  id: string;
  reminder_id: string;
  schedule_version: string;
  device_id: string;
  notice_type: Notice;
  scheduled_for: string;
  attempt_count: number;
};

async function fetchAccessToken(account: ServiceAccount): Promise<string> {
  const key = await importPKCS8(account.private_key, "RS256");
  const now = Math.floor(Date.now() / 1000);
  const assertion = await new SignJWT({
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(account.client_email)
    .setSubject(account.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key);
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const body = await response.json().catch(() => null);
  return parseOAuthResponse(response.status, body).accessToken;
}

function environment() {
  return {
    CRON_SECRET: Deno.env.get("CRON_SECRET"),
    FIREBASE_PROJECT_ID: Deno.env.get("FIREBASE_PROJECT_ID"),
    FIREBASE_SERVICE_ACCOUNT_JSON: Deno.env.get(
      "FIREBASE_SERVICE_ACCOUNT_JSON",
    ),
    SUPABASE_URL: Deno.env.get("SUPABASE_URL"),
    SUPABASE_SERVICE_ROLE_KEY: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
  };
}

async function claimEvent(
  db: SupabaseClient,
  reminder: Reminder,
  device: Device,
  notice: Notice,
  scheduledFor: string,
  summary: OperationalSummary,
): Promise<ClaimedEvent | null> {
  const { data, error } = await db.rpc("claim_payment_notification_event", {
    p_reminder_id: reminder.id,
    p_schedule_version: reminder.schedule_version,
    p_device_id: device.id,
    p_notice_type: notice,
    p_scheduled_for: scheduledFor,
  });
  if (error) {
    summary.administrativeErrors++;
    return null;
  }
  return (data?.[0] as ClaimedEvent | undefined) ?? null;
}

async function updateFailure(
  db: SupabaseClient,
  event: ClaimedEvent,
  decision: ReturnType<typeof classifyFcmError>,
  device: Device,
  summary: OperationalSummary,
) {
  const attempts = event.attempt_count + 1;
  const exhausted = attempts >= MAX_ATTEMPTS;
  const permanent = decision.permanent || exhausted;
  const retryAt = permanent ? null : nextRetryAt(attempts)?.toISOString();
  const { error } = await db.from("payment_notification_events").update({
    status: permanent ? "permanent_failure" : "temporary_failure",
    attempt_count: attempts,
    last_error_code: (exhausted ? "MAX_ATTEMPTS" : decision.code).slice(0, 120),
    next_retry_at: retryAt,
    updated_at: new Date().toISOString(),
  }).eq("id", event.event_id);
  if (error) summary.administrativeErrors++;

  if (permanent) summary.permanentFailures++;
  else summary.temporaryFailures++;

  if (decision.deactivateDevice) {
    const { error: deviceError } = await db.from("fcm_devices").update({
      active: false,
      updated_at: new Date().toISOString(),
    }).eq("id", device.id);
    if (deviceError) summary.administrativeErrors++;
  }
}

async function deliver(
  db: SupabaseClient,
  config: RuntimeConfig,
  getAccessToken: () => Promise<string>,
  reminder: Reminder,
  device: Device,
  notice: Notice,
  event: ClaimedEvent,
  summary: OperationalSummary,
) {
  const [eventResult, reminderResult] = await Promise.all([
    db.from("payment_notification_events")
      .select("id,status,schedule_version,scheduled_for")
      .eq("id", event.event_id).maybeSingle(),
    db.from("payment_reminders")
      .select("id,active,schedule_version,payment_date")
      .eq("id", reminder.id).maybeSingle(),
  ]);
  if (eventResult.error || reminderResult.error) {
    summary.administrativeErrors++;
    return;
  }
  const currentEvent = eventResult.data;
  const currentReminder = reminderResult.data;
  const blockReason = finalDeliveryBlockReason({
    eventExists: currentEvent != null,
    eventStatus: currentEvent?.status,
    eventScheduleVersion: currentEvent?.schedule_version,
    eventScheduledFor: currentEvent?.scheduled_for,
    reminderExists: currentReminder != null,
    reminderActive: currentReminder?.active,
    reminderScheduleVersion: currentReminder?.schedule_version,
    reminderPaymentDate: currentReminder?.payment_date,
  });
  if (blockReason != null) {
    if (blockReason === "EVENT_CANCELLED") {
      summary.skippedCancelled++;
    } else {
      summary.skippedStale++;
      if (currentEvent?.status === "processing") {
        const { error } = await db.from("payment_notification_events").update({
          status: "cancelled",
          last_error_code: blockReason,
          next_retry_at: null,
          updated_at: new Date().toISOString(),
        }).eq("id", event.event_id).eq("status", "processing");
        if (error) summary.administrativeErrors++;
      }
    }
    return;
  }

  try {
    const accessToken = await getAccessToken();
    const response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${config.firebaseProjectId}/messages:send`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify(buildFcmPayload({
          deviceToken: device.token,
          facturaId: reminder.factura_id,
          reminderId: reminder.id,
          notice,
        })),
      },
    );
    const result = await response.json().catch(() => ({}));
    if (!response.ok) {
      await updateFailure(
        db,
        event,
        classifyFcmError(response.status, result),
        device,
        summary,
      );
      return;
    }

    summary.sent++;
    const messageName = typeof result?.name === "string" ? result.name : null;
    const { error } = await db.from("payment_notification_events").update({
      status: "sent",
      attempt_count: event.attempt_count + 1,
      fcm_message_id: messageName,
      sent_at: new Date().toISOString(),
      last_error_code: null,
      next_retry_at: null,
      updated_at: new Date().toISOString(),
    }).eq("id", event.event_id);
    if (error) summary.administrativeErrors++;
  } catch {
    await updateFailure(
      db,
      event,
      classifyThrownError(),
      device,
      summary,
    );
  }
}

async function processReminder(
  db: SupabaseClient,
  config: RuntimeConfig,
  getAccessToken: () => Promise<string>,
  reminder: Reminder,
  notice: Notice,
  scheduledFor: string,
  summary: OperationalSummary,
) {
  summary.processed++;
  const [deviceResult, memberResult] = await Promise.all([
    db.from("fcm_devices").select("id,user_id,organization_id,token,active")
      .eq("organization_id", reminder.organization_id).eq("active", true),
    db.from("organization_members").select("user_id")
      .eq("organization_id", reminder.organization_id).eq("active", true),
  ]);
  let devices: Device[];
  try {
    const candidates = requireDeviceQuery(
      deviceResult.data as Device[] | null,
      deviceResult.error,
    );
    const members = requireDeviceQuery(
      memberResult.data as { user_id: string }[] | null,
      memberResult.error,
    );
    const activeUsers = new Set(members.map((member) => member.user_id));
    devices = filterEnterpriseDevices(
      candidates,
      reminder.organization_id,
      activeUsers,
    );
  } catch {
    summary.administrativeErrors++;
    return;
  }

  if (devices.length === 0) {
    const { error } = await db.from("payment_notification_events").insert({
      reminder_id: reminder.id,
      schedule_version: reminder.schedule_version,
      device_id: null,
      notice_type: notice,
      scheduled_for: scheduledFor,
      status: "no_devices",
    });
    if (error && error.code !== "23505") summary.administrativeErrors++;
    summary.noDevices++;
    return;
  }

  await mapLimit(
    devices,
    DEVICE_CONCURRENCY,
    async (device) => {
      const event = await claimEvent(
        db,
        reminder,
        device,
        notice,
        scheduledFor,
        summary,
      );
      if (!event) return;
      await deliver(
        db,
        config,
        getAccessToken,
        reminder,
        device,
        notice,
        event,
        summary,
      );
    },
    () => summary.administrativeErrors++,
  );
}

async function processNewNotices(
  db: SupabaseClient,
  config: RuntimeConfig,
  getAccessToken: () => Promise<string>,
  summary: OperationalSummary,
) {
  const today = guayaquilDate();
  for (
    const [notice, flag] of [
      ["three_days", "notify_three_days"],
      ["one_day", "notify_one_day"],
    ] as const
  ) {
    const due = dueDateForNotice(today, notice);
    let cursor: string | null = null;
    while (true) {
      let query = db.from("payment_reminders")
        .select(
          "id,user_id,organization_id,factura_id,schedule_version,payment_date",
        )
        .eq("active", true).eq(flag, true).eq("payment_date", due)
        .order("id", { ascending: true }).limit(PAGE_SIZE);
      if (cursor) query = query.gt("id", cursor);
      const { data, error } = await query;
      if (error) {
        summary.administrativeErrors++;
        break;
      }
      const reminders = (data ?? []) as Reminder[];
      for (const reminder of reminders) {
        await processReminder(
          db,
          config,
          getAccessToken,
          reminder,
          notice,
          due,
          summary,
        );
      }
      if (reminders.length < PAGE_SIZE) break;
      cursor = reminders.at(-1)!.id;
    }
  }
}

async function markUnusableRetry(
  db: SupabaseClient,
  eventId: string,
  code: string,
  summary: OperationalSummary,
) {
  const { error } = await db.from("payment_notification_events").update({
    status: "permanent_failure",
    last_error_code: code,
    next_retry_at: null,
    updated_at: new Date().toISOString(),
  }).eq("id", eventId);
  if (error) summary.administrativeErrors++;
  else summary.permanentFailures++;
}

async function processRetry(
  db: SupabaseClient,
  config: RuntimeConfig,
  getAccessToken: () => Promise<string>,
  retry: RetryEvent,
  summary: OperationalSummary,
) {
  summary.processed++;
  const [reminderResult, deviceResult] = await Promise.all([
    db.from("payment_reminders")
      .select(
        "id,user_id,organization_id,factura_id,schedule_version,payment_date,active,notify_three_days,notify_one_day",
      )
      .eq("id", retry.reminder_id).maybeSingle(),
    db.from("fcm_devices").select("id,user_id,organization_id,token,active")
      .eq("id", retry.device_id).maybeSingle(),
  ]);
  if (reminderResult.error || deviceResult.error) {
    summary.administrativeErrors++;
    return;
  }
  const reminder = reminderResult.data as Reminder | null;
  const device = deviceResult.data as Device | null;
  if (!reminder) {
    await markUnusableRetry(db, retry.id, "REMINDER_MISSING", summary);
    return;
  }
  const blockReason = retryBlockReason({
    active: reminder.active ?? false,
    currentScheduleVersion: reminder.schedule_version,
    eventScheduleVersion: retry.schedule_version,
    notice: retry.notice_type,
    notifyThreeDays: reminder.notify_three_days ?? false,
    notifyOneDay: reminder.notify_one_day ?? false,
  });
  if (blockReason) {
    await markUnusableRetry(db, retry.id, blockReason, summary);
    return;
  }
  const membership = device?.user_id
    ? await db.from("organization_members").select("user_id")
      .eq("organization_id", reminder.organization_id)
      .eq("user_id", device.user_id).eq("active", true).maybeSingle()
    : { data: null, error: null };
  if (membership.error) {
    summary.administrativeErrors++;
    return;
  }
  if (
    !device || !device.active ||
    device.organization_id !== reminder.organization_id || !membership.data
  ) {
    await markUnusableRetry(db, retry.id, "DEVICE_INACTIVE", summary);
    return;
  }
  const event = await claimEvent(
    db,
    reminder,
    device,
    retry.notice_type,
    retry.scheduled_for,
    summary,
  );
  if (!event) return;
  await deliver(
    db,
    config,
    getAccessToken,
    reminder,
    device,
    retry.notice_type,
    event,
    summary,
  );
}

async function processRetries(
  db: SupabaseClient,
  config: RuntimeConfig,
  getAccessToken: () => Promise<string>,
  summary: OperationalSummary,
) {
  const now = new Date();
  const queues = [
    {
      status: "temporary_failure",
      dueColumn: "next_retry_at",
      cutoff: now.toISOString(),
    },
    {
      status: "processing",
      dueColumn: "claimed_at",
      cutoff: processingRecoveryCutoff(now).toISOString(),
    },
  ] as const;
  for (const queue of queues) {
    let cursor: string | null = null;
    while (true) {
      let query = db.from("payment_notification_events")
        .select(
          "id,reminder_id,schedule_version,device_id,notice_type,scheduled_for,attempt_count",
        )
        .eq("status", queue.status).lte(queue.dueColumn, queue.cutoff)
        .lt("attempt_count", MAX_ATTEMPTS).not("device_id", "is", null)
        .order("id", { ascending: true }).limit(PAGE_SIZE);
      if (cursor) query = query.gt("id", cursor);
      const { data, error } = await query;
      if (error) {
        summary.administrativeErrors++;
        break;
      }
      const retries = (data ?? []) as RetryEvent[];
      await mapLimit(
        retries,
        DEVICE_CONCURRENCY,
        (retry) =>
          processRetry(
            db,
            config,
            getAccessToken,
            retry,
            summary,
          ),
        () => summary.administrativeErrors++,
      );
      if (retries.length < PAGE_SIZE) break;
      cursor = retries.at(-1)!.id;
    }
  }
}

export async function handler(request: Request): Promise<Response> {
  if (request.method !== "POST") {
    return new Response("Method Not Allowed", {
      status: 405,
      headers: { allow: "POST" },
    });
  }

  let config: RuntimeConfig;
  try {
    config = validateRuntimeConfig(environment());
  } catch {
    return Response.json({ ...emptySummary(), administrativeErrors: 1 }, {
      status: 500,
    });
  }
  if (
    request.headers.get("authorization") !== `Bearer ${config.cronSecret}`
  ) {
    return new Response("Unauthorized", { status: 401 });
  }

  const summary = emptySummary();
  const db = createClient(
    config.supabaseUrl,
    config.supabaseServiceRoleKey,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
  let tokenPromise: Promise<string> | null = null;
  const getAccessToken = () =>
    tokenPromise ??= fetchAccessToken(config.serviceAccount);

  try {
    // Entrega "al menos una vez": los processing abandonados se recuperan.
    // Si FCM aceptó un mensaje pero falló status=sent, puede ocurrir un
    // duplicado excepcional; se prioriza no perder la notificación.
    await processNewNotices(db, config, getAccessToken, summary);
    await processRetries(db, config, getAccessToken, summary);
    return Response.json(summary);
  } catch {
    summary.administrativeErrors++;
    return Response.json(summary, { status: 500 });
  }
}

if (import.meta.main) Deno.serve(handler);
