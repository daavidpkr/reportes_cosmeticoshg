import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";

import {
  buildFcmPayload,
  classifyFcmError,
  classifyThrownError,
  dueDateForNotice,
  filterEnterpriseDevices,
  finalDeliveryBlockReason,
  guayaquilDate,
  mapLimit,
  MAX_ATTEMPTS,
  nextRetryAt,
  parseOAuthResponse,
  processingRecoveryCutoff,
  requireDeviceQuery,
  retryBlockReason,
  validateRuntimeConfig,
} from "./core.ts";
import { handler } from "./index.ts";

const validEnvironment = {
  CRON_SECRET: "cron-secret",
  FIREBASE_PROJECT_ID: "firebase-project",
  FIREBASE_SERVICE_ACCOUNT_JSON: JSON.stringify({
    client_email: "sender@example.test",
    private_key: "private-key-placeholder",
    project_id: "firebase-project",
  }),
  SUPABASE_URL: "https://project.supabase.co",
  SUPABASE_SERVICE_ROLE_KEY: "service-role-placeholder",
};

Deno.test("enterprise devices include only active members of the organization", () => {
  const devices = [
    { id: "a", user_id: "u1", organization_id: "org1" },
    { id: "b", user_id: "u2", organization_id: "org1" },
    { id: "c", user_id: "u1", organization_id: "org2" },
  ];
  assertEquals(
    filterEnterpriseDevices(devices, "org1", new Set(["u1"])).map((d) => d.id),
    ["a"],
  );
});

Deno.test("final delivery only accepts the current processing schedule", () => {
  const valid = {
    eventExists: true,
    eventStatus: "processing",
    eventScheduleVersion: "v2",
    eventScheduledFor: "2026-08-17",
    reminderExists: true,
    reminderActive: true,
    reminderScheduleVersion: "v2",
    reminderPaymentDate: "2026-08-17",
  };
  assertEquals(finalDeliveryBlockReason(valid), null);
  assertEquals(
    finalDeliveryBlockReason({ ...valid, eventExists: false }),
    "EVENT_MISSING",
  );
  assertEquals(
    finalDeliveryBlockReason({ ...valid, eventStatus: "cancelled" }),
    "EVENT_CANCELLED",
  );
  assertEquals(
    finalDeliveryBlockReason({ ...valid, eventStatus: "sent" }),
    "EVENT_NOT_PROCESSING",
  );
  assertEquals(
    finalDeliveryBlockReason({ ...valid, reminderActive: false }),
    "REMINDER_INACTIVE",
  );
  assertEquals(
    finalDeliveryBlockReason({ ...valid, reminderScheduleVersion: "v3" }),
    "SCHEDULE_CHANGED",
  );
  assertEquals(
    finalDeliveryBlockReason({ ...valid, reminderPaymentDate: "2026-08-18" }),
    "DATE_CHANGED",
  );
});

Deno.test("rechaza métodos distintos de POST", async () => {
  const response = await handler(
    new Request("https://example.test/process-payment-reminders", {
      method: "GET",
    }),
  );
  assertEquals(response.status, 405);
  assertEquals(response.headers.get("allow"), "POST");
});

Deno.test("calcula el aviso de tres días", () => {
  assertEquals(dueDateForNotice("2026-08-10", "three_days"), "2026-08-13");
});

Deno.test("calcula el aviso de un día", () => {
  assertEquals(dueDateForNotice("2026-08-10", "one_day"), "2026-08-11");
});

Deno.test("America/Guayaquil cambia de fecha a las 05:00 UTC", () => {
  assertEquals(
    guayaquilDate(new Date("2026-08-10T04:59:59Z")),
    "2026-08-09",
  );
  assertEquals(
    guayaquilDate(new Date("2026-08-10T05:00:00Z")),
    "2026-08-10",
  );
});

Deno.test("el payload no contiene datos financieros sensibles", () => {
  const payload = buildFcmPayload({
    deviceToken: "token-placeholder",
    facturaId: "FAC-1",
    reminderId: "REM-1",
    notice: "three_days",
  });
  const encoded = JSON.stringify(payload).toLowerCase();
  assertEquals(payload.message.data.type, "recordatorio_pago");
  assertEquals(
    payload.message.android.notification.channel_id,
    "recordatorios_pago",
  );
  for (const forbidden of ["monto", "saldo", "cliente", "venta", "abono"]) {
    assert(!encoded.includes(forbidden));
  }
});

Deno.test("acepta una configuración Firebase válida", () => {
  const config = validateRuntimeConfig(validEnvironment);
  assertEquals(config.firebaseProjectId, "firebase-project");
  assertEquals(config.serviceAccount.project_id, "firebase-project");
});

Deno.test("rechaza JSON y campos Firebase inválidos", () => {
  assertThrows(
    () =>
      validateRuntimeConfig({
        ...validEnvironment,
        FIREBASE_SERVICE_ACCOUNT_JSON: "not-json",
      }),
    Error,
    "invalid_configuration",
  );
  assertThrows(
    () =>
      validateRuntimeConfig({
        ...validEnvironment,
        FIREBASE_SERVICE_ACCOUNT_JSON: JSON.stringify({
          client_email: "",
          private_key: "key",
          project_id: "firebase-project",
        }),
      }),
    Error,
    "invalid_configuration",
  );
});

Deno.test("rechaza project_id cruzado", () => {
  assertThrows(
    () =>
      validateRuntimeConfig({
        ...validEnvironment,
        FIREBASE_PROJECT_ID: "other-project",
      }),
    Error,
    "FIREBASE_PROJECT_ID_MISMATCH",
  );
});

Deno.test("valida access_token y expires_in de OAuth", () => {
  assertEquals(
    parseOAuthResponse(200, { access_token: "access", expires_in: 3600 }),
    { accessToken: "access", expiresIn: 3600 },
  );
  assertThrows(() => parseOAuthResponse(401, {}), Error, "oauth_http_401");
  assertThrows(
    () => parseOAuthResponse(200, { access_token: "", expires_in: 0 }),
    Error,
    "oauth_invalid_response",
  );
});

function fcmBody(errorCode: string, field?: string) {
  return {
    error: {
      status: "INVALID_ARGUMENT",
      details: [
        {
          "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
          errorCode,
        },
        ...(field
          ? [{
            "@type": "type.googleapis.com/google.rpc.BadRequest",
            fieldViolations: [{ field }],
          }]
          : []),
      ],
    },
  };
}

Deno.test("UNREGISTERED desactiva el dispositivo", () => {
  assertEquals(classifyFcmError(404, fcmBody("UNREGISTERED")), {
    code: "UNREGISTERED",
    permanent: true,
    deactivateDevice: true,
  });
});

Deno.test("SENDER_ID_MISMATCH desactiva el dispositivo", () => {
  assertEquals(classifyFcmError(403, fcmBody("SENDER_ID_MISMATCH")), {
    code: "SENDER_ID_MISMATCH",
    permanent: true,
    deactivateDevice: true,
  });
});

Deno.test("INVALID_ARGUMENT de payload no desactiva el dispositivo", () => {
  assertEquals(
    classifyFcmError(400, fcmBody("INVALID_ARGUMENT", "message.android")),
    {
      code: "INVALID_ARGUMENT",
      permanent: true,
      deactivateDevice: false,
    },
  );
});

Deno.test("INVALID_ARGUMENT inequívoco del token sí lo desactiva", () => {
  assertEquals(
    classifyFcmError(400, fcmBody("INVALID_ARGUMENT", "message.token")),
    {
      code: "INVALID_ARGUMENT",
      permanent: true,
      deactivateDevice: true,
    },
  );
});

Deno.test("un error de red es temporal", () => {
  assertEquals(classifyThrownError(), {
    code: "NETWORK_ERROR",
    permanent: false,
    deactivateDevice: false,
  });
});

Deno.test("aplica backoff y máximo de intentos", () => {
  const now = new Date("2026-08-10T13:00:00Z");
  assertEquals(
    nextRetryAt(1, now)?.toISOString(),
    "2026-08-10T13:30:00.000Z",
  );
  assertEquals(
    nextRetryAt(2, now)?.toISOString(),
    "2026-08-10T14:00:00.000Z",
  );
  assertEquals(nextRetryAt(MAX_ATTEMPTS, now), null);
});

Deno.test("recupera processing después de diez minutos", () => {
  const now = new Date("2026-08-10T13:20:00Z");
  assertEquals(
    processingRecoveryCutoff(now).toISOString(),
    "2026-08-10T13:10:00.000Z",
  );
});

Deno.test("no reintenta una versión de fecha anterior", () => {
  assertEquals(
    retryBlockReason({
      active: true,
      currentScheduleVersion: "new-version",
      eventScheduleVersion: "old-version",
      notice: "one_day",
      notifyThreeDays: true,
      notifyOneDay: true,
    }),
    "SCHEDULE_CHANGED",
  );
});

Deno.test("no reintenta un tipo de aviso deshabilitado", () => {
  assertEquals(
    retryBlockReason({
      active: true,
      currentScheduleVersion: "same-version",
      eventScheduleVersion: "same-version",
      notice: "three_days",
      notifyThreeDays: false,
      notifyOneDay: true,
    }),
    "NOTICE_DISABLED",
  );
});

Deno.test("un error de consulta no se convierte en sin dispositivos", () => {
  assertThrows(
    () => requireDeviceQuery(null, { message: "database unavailable" }),
    Error,
    "device_query_failed",
  );
});

Deno.test("distingue correctamente el caso sin dispositivos", () => {
  assertEquals(requireDeviceQuery([], null), []);
});

Deno.test("un error parcial no interrumpe el lote", async () => {
  const completed: number[] = [];
  const errors: unknown[] = [];
  await mapLimit(
    [1, 2, 3],
    2,
    (value) => {
      if (value === 2) return Promise.reject(new Error("temporary"));
      completed.push(value);
      return Promise.resolve();
    },
    (error) => errors.push(error),
  );
  assertEquals(completed.sort(), [1, 3]);
  assertEquals(errors.length, 1);
});

Deno.test("mapLimit también aísla rechazos asincrónicos", async () => {
  const errors: unknown[] = [];
  await assertRejects(
    () => Promise.reject(new Error("control")),
    Error,
    "control",
  );
  await mapLimit(
    [1],
    1,
    () => Promise.reject(new Error("isolated")),
    (error) => errors.push(error),
  );
  assertEquals(errors.length, 1);
});
