import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { importPKCS8, SignJWT } from "jose";
import {
  buildNotificationTestPayload,
  buildSameDayFcmPayload,
  classifyFcmError,
  type EligibleInvoice,
  emptySummary,
  guayaquilDate,
  mapLimit,
  type OperationalSummary,
  parseOAuthResponse,
  type RuntimeConfig,
  selectUserSyntheticDevices,
  type ServiceAccount,
  validateRuntimeConfig,
} from "./core.ts";

type EligibleRow = {
  organization_id: string;
  reminder_id: string;
  factura_id: string;
  invoice_number: string;
  cliente: string;
  balance: number | string;
  notification_date: string;
};
type Device = {
  id: string;
  user_id: string;
  organization_id: string;
  token: string;
  platform?: string;
  last_seen_at?: string;
};

type SyntheticSummary = {
  eligible_devices: number;
  successful_sends: number;
  invalid_tokens: number;
  failures: number;
  duplicates_omitted: number;
  local_date: string;
};

async function fetchAccessToken(account: ServiceAccount): Promise<string> {
  const key = await importPKCS8(account.private_key, "RS256");
  const now = Math.floor(Date.now() / 1000);
  const assertion = await new SignJWT({
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" }).setIssuer(
      account.client_email,
    )
    .setSubject(account.client_email).setAudience(
      "https://oauth2.googleapis.com/token",
    )
    .setIssuedAt(now).setExpirationTime(now + 3600).sign(key);
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  return parseOAuthResponse(
    response.status,
    await response.json().catch(() => null),
  ).accessToken;
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

function invoice(row: EligibleRow): EligibleInvoice {
  return {
    reminderId: row.reminder_id,
    facturaId: row.factura_id,
    invoiceNumber: row.invoice_number,
    cliente: row.cliente,
    balance: Number(row.balance),
  };
}

async function sendToDevice(
  db: SupabaseClient,
  config: RuntimeConfig,
  accessToken: () => Promise<string>,
  device: Device,
  date: string,
  invoices: EligibleInvoice[],
  summary: OperationalSummary,
) {
  const { data: deliveryId, error: claimError } = await db.rpc(
    "claim_same_day_payment_delivery",
    {
      p_organization_id: device.organization_id,
      p_user_id: device.user_id,
      p_device_id: device.id,
      p_notification_date: date,
      p_invoice_count: invoices.length,
    },
  );
  if (claimError) {
    summary.administrativeErrors++;
    return;
  }
  if (!deliveryId) return;
  summary.processed++;
  try {
    const response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${config.firebaseProjectId}/messages:send`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${await accessToken()}`,
          "content-type": "application/json",
        },
        body: JSON.stringify(
          buildSameDayFcmPayload({
            deviceToken: device.token,
            localDate: date,
            invoices,
          }),
        ),
      },
    );
    const result = await response.json().catch(() => ({}));
    if (!response.ok) {
      const decision = classifyFcmError(response.status, result);
      await db.from("payment_notification_deliveries").update({
        status: decision.deactivateDevice ? "invalid_token" : "failed",
        failure_code: decision.code.slice(0, 120),
        attempt_count: 1,
        updated_at: new Date().toISOString(),
      }).eq("id", deliveryId);
      if (decision.deactivateDevice) {
        await db.from("fcm_devices").update({ active: false }).eq(
          "id",
          device.id,
        );
      }
      if (decision.permanent) summary.permanentFailures++;
      else summary.temporaryFailures++;
      return;
    }
    await db.from("payment_notification_deliveries").update({
      status: "sent",
      provider_message_id: typeof result?.name === "string"
        ? result.name
        : null,
      attempt_count: 1,
      sent_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    }).eq("id", deliveryId);
    summary.sent++;
  } catch {
    await db.from("payment_notification_deliveries").update({
      status: "failed",
      failure_code: "NETWORK_ERROR",
      attempt_count: 1,
      updated_at: new Date().toISOString(),
    }).eq("id", deliveryId);
    summary.temporaryFailures++;
  }
}

async function processToday(
  db: SupabaseClient,
  config: RuntimeConfig,
  accessToken: () => Promise<string>,
  summary: OperationalSummary,
) {
  const { data, error } = await db.rpc(
    "list_same_day_payment_notification_invoices",
  );
  if (error) throw new Error("eligible_invoice_query_failed");
  const date = guayaquilDate();
  const byOrganization = new Map<string, EligibleInvoice[]>();
  for (const row of (data ?? []) as EligibleRow[]) {
    if (row.notification_date !== date) continue;
    const values = byOrganization.get(row.organization_id) ?? [];
    values.push(invoice(row));
    byOrganization.set(row.organization_id, values);
  }
  for (const [organizationId, invoices] of byOrganization) {
    const [devicesResult, membersResult] = await Promise.all([
      db.from("fcm_devices").select("id,user_id,organization_id,token").eq(
        "organization_id",
        organizationId,
      ).eq("active", true),
      db.from("organization_members").select("user_id").eq(
        "organization_id",
        organizationId,
      ).eq("active", true),
    ]);
    if (devicesResult.error || membersResult.error) {
      summary.administrativeErrors++;
      continue;
    }
    const members = new Set(
      ((membersResult.data ?? []) as { user_id: string }[]).map((member) =>
        member.user_id
      ),
    );
    const devices = ((devicesResult.data ?? []) as Device[]).filter((device) =>
      members.has(device.user_id)
    );
    if (devices.length === 0) {
      summary.noDevices++;
      continue;
    }
    await mapLimit(
      devices,
      6,
      (device) =>
        sendToDevice(db, config, accessToken, device, date, invoices, summary),
      () => summary.administrativeErrors++,
    );
  }
}

async function handleNotificationTest(
  request: Request,
  db: SupabaseClient,
  config: RuntimeConfig,
): Promise<Response> {
  const authorization = request.headers.get("authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) {
    return new Response("Unauthorized", { status: 401 });
  }
  const { data: userData, error: userError } = await db.auth.getUser(
    authorization.slice(7),
  );
  if (userError || !userData.user) {
    return new Response("Unauthorized", { status: 401 });
  }
  const body = await request.json().catch(() => null) as
    | { device_id?: unknown; request_id?: unknown }
    | null;
  const deviceId = typeof body?.device_id === "string" ? body.device_id : "";
  const requestId = typeof body?.request_id === "string" ? body.request_id : "";
  if (
    !/^[0-9a-f-]{36}$/i.test(deviceId) || !/^[0-9a-f-]{36}$/i.test(requestId)
  ) {
    return Response.json({ status: "invalid_request" }, { status: 400 });
  }
  const localDate = guayaquilDate();
  const claim = await db.rpc("claim_notification_test_delivery", {
    p_user_id: userData.user.id,
    p_device_id: deviceId,
    p_request_id: requestId,
    p_local_date: localDate,
  });
  if (claim.error) return Response.json({ status: "failed" }, { status: 500 });
  if (!claim.data) {
    return Response.json({ status: "duplicate_or_rate_limited" });
  }
  const device = await db.from("fcm_devices").select("token").eq(
    "id",
    deviceId,
  ).eq("user_id", userData.user.id).eq("active", true).maybeSingle();
  if (device.error || !device.data) {
    await db.from("notification_test_deliveries").update({
      status: "failed",
      failure_code: "DEVICE_UNAVAILABLE",
    }).eq("id", claim.data);
    return Response.json({ status: "device_unavailable" }, { status: 404 });
  }
  try {
    const response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${config.firebaseProjectId}/messages:send`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${await fetchAccessToken(
            config.serviceAccount,
          )}`,
          "content-type": "application/json",
        },
        body: JSON.stringify(buildNotificationTestPayload({
          deviceToken: device.data.token,
          localDate,
        })),
      },
    );
    const result = await response.json().catch(() => ({}));
    if (!response.ok) {
      const decision = classifyFcmError(response.status, result);
      await db.from("notification_test_deliveries").update({
        status: decision.deactivateDevice ? "invalid_token" : "failed",
        failure_code: decision.code.slice(0, 120),
      }).eq("id", claim.data);
      if (decision.deactivateDevice) {
        await db.from("fcm_devices").update({ active: false }).eq(
          "id",
          deviceId,
        );
      }
      return Response.json(
        { status: "provider_rejected", code: decision.code },
        {
          status: 502,
        },
      );
    }
    await db.from("notification_test_deliveries").update({
      status: "sent",
      provider_message_id: typeof result?.name === "string"
        ? result.name
        : null,
      sent_at: new Date().toISOString(),
    }).eq("id", claim.data);
    return Response.json({ status: "sent", local_date: localDate });
  } catch {
    await db.from("notification_test_deliveries").update({
      status: "failed",
      failure_code: "NETWORK_ERROR",
    }).eq("id", claim.data);
    return Response.json({ status: "provider_unavailable" }, { status: 503 });
  }
}

async function authenticatedUser(request: Request, db: SupabaseClient) {
  const authorization = request.headers.get("authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) return null;
  const result = await db.auth.getUser(authorization.slice(7));
  return result.error ? null : result.data.user;
}

async function handleUserNotificationTest(
  request: Request,
  db: SupabaseClient,
  config: RuntimeConfig,
): Promise<Response> {
  const user = await authenticatedUser(request, db);
  if (!user) return new Response("Unauthorized", { status: 401 });
  const body = await request.json().catch(() => null) as
    | { operation?: unknown; execution_id?: unknown }
    | null;
  const operation = body?.operation;
  if (operation !== "preview" && operation !== "send") {
    return Response.json({ status: "invalid_operation" }, { status: 400 });
  }

  const localDate = guayaquilDate();

  if (operation === "preview") {
    const devicesResult = await db.from("fcm_devices")
      .select("id,user_id,organization_id,token,platform,active,last_seen_at")
      .eq("user_id", user.id).eq("platform", "android")
      .order("last_seen_at", { ascending: false });
    if (devicesResult.error) {
      return Response.json({ status: "preparation_failed" }, { status: 500 });
    }
    const allDevices = (devicesResult.data ?? []) as (Device & {
      platform: string; active: boolean;
    })[];
    const { eligible, inactive, duplicates } = selectUserSyntheticDevices(
      allDevices,
      user.id,
    );
    const execution = await db.from("notification_test_executions").insert({
      requested_by: user.id,
      operation: "user_android_test",
      local_date: localDate,
      eligible_count: eligible.length,
      inactive_count: inactive,
      duplicate_count: duplicates,
    }).select("id").single();
    if (execution.error || !execution.data) {
      return Response.json({ status: "preparation_failed" }, { status: 500 });
    }
    if (eligible.length > 0) {
      const recipients = await db.from("notification_test_recipients").insert(
        await Promise.all(eligible.map(async (device) => ({
          execution_id: execution.data.id,
          device_id: device.id,
          token_fingerprint: await crypto.subtle.digest(
            "SHA-256",
            new TextEncoder().encode(device.token),
          ).then((hash) =>
            Array.from(new Uint8Array(hash)).map((b) =>
              b.toString(16).padStart(2, "0")
            ).join("")
          ),
        }))),
      );
      if (recipients.error) {
        await db.from("notification_test_executions").update({
          status: "failed",
        })
          .eq("id", execution.data.id);
        return Response.json({ status: "preparation_failed" }, { status: 500 });
      }
    }
    return Response.json({
      eligible_devices: eligible.length,
      inactive_devices: inactive,
      duplicates_omitted: duplicates,
      execution_id: execution.data.id,
    }, { headers: { "x-notification-test-execution": execution.data.id } });
  }

  const executionId = typeof body?.execution_id === "string"
    ? body.execution_id
    : "";
  if (!/^[0-9a-f-]{36}$/i.test(executionId)) {
    return Response.json({ status: "invalid_request" }, { status: 400 });
  }
  const execution = await db.from("notification_test_executions").select("*")
    .eq("id", executionId).eq("requested_by", user.id)
    .eq("operation", "user_android_test")
    .eq("status", "prepared").maybeSingle();
  if (
    execution.error || !execution.data ||
    execution.data.local_date !== localDate
  ) {
    return Response.json({ status: "execution_unavailable" }, { status: 409 });
  }
  const claimed = await db.from("notification_test_executions").update({
    status: "sending",
    started_at: new Date().toISOString(),
  }).eq("id", executionId).eq("status", "prepared").select("id").maybeSingle();
  if (claimed.error || !claimed.data) {
    return Response.json({ status: "execution_unavailable" }, { status: 409 });
  }
  const recipients = await db.from("notification_test_recipients")
    .select("device_id,token_fingerprint").eq("execution_id", executionId)
    .eq("status", "prepared");
  if (recipients.error) {
    await db.from("notification_test_executions").update({ status: "failed" })
      .eq("id", executionId);
    return Response.json({ status: "recipient_query_failed" }, {
      status: 500,
    });
  }
  const preparedRecipients = (recipients.data ?? []) as {
    device_id: string;
    token_fingerprint: string;
  }[];
  let sent = 0, invalid = 0, failures = 0, skipped = 0;
  let accessToken: Promise<string> | null = null;
  await mapLimit(preparedRecipients, 6, async (recipient) => {
    const device = await db.from("fcm_devices")
      .select("id,user_id,organization_id,token,platform,active")
      .eq("id", recipient.device_id).eq("user_id", user.id)
      .eq("platform", "android").eq("active", true).maybeSingle();
    const token = device.data?.token?.trim() ?? "";
    const fingerprint = token
      ? await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token))
        .then((hash) =>
          Array.from(new Uint8Array(hash)).map((b) =>
            b.toString(16).padStart(2, "0")
          ).join("")
        )
      : "";
    if (
      !device.data ||
      fingerprint !== recipient.token_fingerprint
    ) {
      skipped++;
      await db.from("notification_test_recipients").update({
        status: "skipped",
        failure_code: "NO_LONGER_ELIGIBLE",
      }).eq("execution_id", executionId).eq("device_id", recipient.device_id);
      return;
    }
    try {
      const response = await fetch(
        `https://fcm.googleapis.com/v1/projects/${config.firebaseProjectId}/messages:send`,
        {
          method: "POST",
          headers: {
            authorization: `Bearer ${await (accessToken ??= fetchAccessToken(
              config.serviceAccount,
            ))}`,
            "content-type": "application/json",
          },
          body: JSON.stringify(
            buildNotificationTestPayload({ deviceToken: token, localDate }),
          ),
        },
      );
      const result = await response.json().catch(() => ({}));
      if (!response.ok) {
        const decision = classifyFcmError(response.status, result);
        if (decision.deactivateDevice) {
          invalid++;
          await db.from("fcm_devices").update({ active: false }).eq(
            "id",
            device.data.id,
          );
        } else failures++;
        await db.from("notification_test_recipients").update({
          status: decision.deactivateDevice ? "invalid_token" : "failed",
          failure_code: decision.code.slice(0, 120),
          attempted_at: new Date().toISOString(),
        }).eq("execution_id", executionId).eq("device_id", recipient.device_id);
        return;
      }
      sent++;
      await db.from("notification_test_recipients").update({
        status: "sent",
        attempted_at: new Date().toISOString(),
        sent_at: new Date().toISOString(),
        provider_message_id: typeof result?.name === "string"
          ? result.name
          : null,
      }).eq("execution_id", executionId).eq("device_id", recipient.device_id);
    } catch {
      failures++;
      await db.from("notification_test_recipients").update({
        status: "failed",
        failure_code: "NETWORK_ERROR",
        attempted_at: new Date().toISOString(),
      }).eq("execution_id", executionId).eq("device_id", recipient.device_id);
    }
  }, () => failures++);
  const summary: SyntheticSummary = {
    eligible_devices: execution.data.eligible_count,
    successful_sends: sent,
    invalid_tokens: invalid,
    failures,
    duplicates_omitted: execution.data.duplicate_count + skipped,
    local_date: localDate,
  };
  await db.from("notification_test_executions").update({
    status: "completed",
    sent_count: sent,
    invalid_token_count: invalid,
    failure_count: failures,
    duplicate_count: summary.duplicates_omitted,
    completed_at: new Date().toISOString(),
  }).eq("id", executionId);
  return Response.json(summary);
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
  const db = createClient(config.supabaseUrl, config.supabaseServiceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  if (
    new URL(request.url).pathname.endsWith("/user-notification-test")
  ) {
    return handleUserNotificationTest(request, db, config);
  }
  if (new URL(request.url).pathname.endsWith("/notification-test")) {
    return handleNotificationTest(request, db, config);
  }
  const authorization = request.headers.get("authorization") ?? "";
  const presentedSecret = authorization.startsWith("Bearer ")
    ? authorization.slice(7)
    : "";
  let authorized = authorization === `Bearer ${config.cronSecret}`;
  if (!authorized && presentedSecret) {
    const result = await db.rpc("authorize_payment_notification_cron", {
      p_secret: presentedSecret,
    });
    authorized = result.error == null && result.data === true;
  }
  if (!authorized) return new Response("Unauthorized", { status: 401 });

  const summary = emptySummary();
  let token: Promise<string> | null = null;
  try {
    await processToday(
      db,
      config,
      () => token ??= fetchAccessToken(config.serviceAccount),
      summary,
    );
    return Response.json(summary);
  } catch {
    summary.administrativeErrors++;
    return Response.json(summary, { status: 500 });
  }
}

if (import.meta.main) Deno.serve(handler);
