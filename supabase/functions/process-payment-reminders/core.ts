export const TIME_ZONE = "America/Guayaquil";
export const MAX_ATTEMPTS = 5;
export const PAGE_SIZE = 200;
export const DEVICE_CONCURRENCY = 6;
export const PROCESSING_RECOVERY_MINUTES = 10;

export type Notice = "three_days" | "one_day";

export type ServiceAccount = {
  client_email: string;
  private_key: string;
  project_id: string;
};

export type RuntimeConfig = {
  cronSecret: string;
  firebaseProjectId: string;
  serviceAccount: ServiceAccount;
  supabaseUrl: string;
  supabaseServiceRoleKey: string;
};

export type FcmErrorDecision = {
  code: string;
  permanent: boolean;
  deactivateDevice: boolean;
};

export type OperationalSummary = {
  processed: number;
  sent: number;
  noDevices: number;
  temporaryFailures: number;
  permanentFailures: number;
  administrativeErrors: number;
  skippedStale: number;
  skippedCancelled: number;
};

export function emptySummary(): OperationalSummary {
  return {
    processed: 0,
    sent: 0,
    noDevices: 0,
    temporaryFailures: 0,
    permanentFailures: 0,
    administrativeErrors: 0,
    skippedStale: 0,
    skippedCancelled: 0,
  };
}

export type FinalDeliveryState = {
  eventExists: boolean;
  eventStatus?: string;
  eventScheduleVersion?: string;
  eventScheduledFor?: string;
  reminderExists: boolean;
  reminderActive?: boolean;
  reminderScheduleVersion?: string;
  reminderPaymentDate?: string;
};

export function finalDeliveryBlockReason(
  state: FinalDeliveryState,
):
  | "EVENT_MISSING"
  | "EVENT_CANCELLED"
  | "EVENT_NOT_PROCESSING"
  | "REMINDER_MISSING"
  | "REMINDER_INACTIVE"
  | "SCHEDULE_CHANGED"
  | "DATE_CHANGED"
  | null {
  if (!state.eventExists) return "EVENT_MISSING";
  if (state.eventStatus === "cancelled") return "EVENT_CANCELLED";
  if (state.eventStatus !== "processing") return "EVENT_NOT_PROCESSING";
  if (!state.reminderExists) return "REMINDER_MISSING";
  if (!state.reminderActive) return "REMINDER_INACTIVE";
  if (state.eventScheduleVersion !== state.reminderScheduleVersion) {
    return "SCHEDULE_CHANGED";
  }
  if (state.eventScheduledFor !== state.reminderPaymentDate) {
    return "DATE_CHANGED";
  }
  return null;
}

export function guayaquilDate(now = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: TIME_ZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(now);
}

export function addDays(date: string, days: number): string {
  const value = new Date(`${date}T12:00:00Z`);
  value.setUTCDate(value.getUTCDate() + days);
  return value.toISOString().slice(0, 10);
}

export function dueDateForNotice(today: string, notice: Notice): string {
  return addDays(today, notice === "three_days" ? 3 : 1);
}

export function visibleContent(input: {
  facturaId: string;
  cliente: string;
  nombreComercial: string;
  notice: Notice;
}) {
  const cliente = input.cliente.trim() || "Sin registrar";
  const nombreComercial = input.nombreComercial.trim() || "Sin registrar";
  const reminder = input.notice === "three_days"
    ? "Tienes un pago programado dentro de 3 días."
    : "Recuerda revisar el pago pendiente para mañana.";
  return {
    title: `Factura ${input.facturaId}`,
    body:
      `Cliente: ${cliente} · Nombre comercial: ${nombreComercial} · ${reminder}`,
  };
}

export function buildFcmPayload(input: {
  deviceToken: string;
  facturaId: string;
  reminderId: string;
  notice: Notice;
  cliente: string;
  nombreComercial: string;
}) {
  return {
    message: {
      token: input.deviceToken,
      notification: visibleContent(input),
      data: {
        type: "recordatorio_pago",
        factura_id: input.facturaId,
        recordatorio_id: input.reminderId,
      },
      android: {
        priority: "high",
        notification: { channel_id: "recordatorios_pago" },
      },
    },
  };
}

function required(value: string | undefined, name: string): string {
  if (!value?.trim()) throw new Error(`missing_configuration:${name}`);
  return value.trim();
}

export function validateRuntimeConfig(values: {
  CRON_SECRET?: string;
  FIREBASE_PROJECT_ID?: string;
  FIREBASE_SERVICE_ACCOUNT_JSON?: string;
  SUPABASE_URL?: string;
  SUPABASE_SERVICE_ROLE_KEY?: string;
}): RuntimeConfig {
  const cronSecret = required(values.CRON_SECRET, "CRON_SECRET");
  const firebaseProjectId = required(
    values.FIREBASE_PROJECT_ID,
    "FIREBASE_PROJECT_ID",
  );
  const rawAccount = required(
    values.FIREBASE_SERVICE_ACCOUNT_JSON,
    "FIREBASE_SERVICE_ACCOUNT_JSON",
  );
  const supabaseUrl = required(values.SUPABASE_URL, "SUPABASE_URL");
  const supabaseServiceRoleKey = required(
    values.SUPABASE_SERVICE_ROLE_KEY,
    "SUPABASE_SERVICE_ROLE_KEY",
  );

  let decoded: unknown;
  try {
    decoded = JSON.parse(rawAccount);
  } catch {
    throw new Error("invalid_configuration:FIREBASE_SERVICE_ACCOUNT_JSON");
  }
  if (!decoded || typeof decoded !== "object") {
    throw new Error("invalid_configuration:FIREBASE_SERVICE_ACCOUNT_JSON");
  }
  const account = decoded as Record<string, unknown>;
  const clientEmail = typeof account.client_email === "string"
    ? account.client_email.trim()
    : "";
  const privateKey = typeof account.private_key === "string"
    ? account.private_key.trim()
    : "";
  const accountProjectId = typeof account.project_id === "string"
    ? account.project_id.trim()
    : "";
  if (!clientEmail || !privateKey || !accountProjectId) {
    throw new Error("invalid_configuration:FIREBASE_SERVICE_ACCOUNT_JSON");
  }
  if (accountProjectId !== firebaseProjectId) {
    throw new Error("invalid_configuration:FIREBASE_PROJECT_ID_MISMATCH");
  }

  return {
    cronSecret,
    firebaseProjectId,
    serviceAccount: {
      client_email: clientEmail,
      private_key: privateKey,
      project_id: accountProjectId,
    },
    supabaseUrl,
    supabaseServiceRoleKey,
  };
}

export function parseOAuthResponse(
  status: number,
  body: unknown,
): { accessToken: string; expiresIn?: number } {
  if (status < 200 || status >= 300) throw new Error(`oauth_http_${status}`);
  if (!body || typeof body !== "object") {
    throw new Error("oauth_invalid_response");
  }
  const value = body as Record<string, unknown>;
  if (typeof value.access_token !== "string" || !value.access_token.trim()) {
    throw new Error("oauth_invalid_response");
  }
  if (
    value.expires_in !== undefined &&
    (typeof value.expires_in !== "number" ||
      !Number.isFinite(value.expires_in) || value.expires_in <= 0)
  ) {
    throw new Error("oauth_invalid_response");
  }
  return {
    accessToken: value.access_token,
    expiresIn: value.expires_in as number | undefined,
  };
}

function fcmDetail(body: unknown): {
  status?: string;
  fcmCode?: string;
  tokenFieldViolation: boolean;
} {
  if (!body || typeof body !== "object") return { tokenFieldViolation: false };
  const error = (body as Record<string, unknown>).error;
  if (!error || typeof error !== "object") {
    return { tokenFieldViolation: false };
  }
  const record = error as Record<string, unknown>;
  const details = Array.isArray(record.details) ? record.details : [];
  let fcmCode: string | undefined;
  let tokenFieldViolation = false;
  for (const detail of details) {
    if (!detail || typeof detail !== "object") continue;
    const item = detail as Record<string, unknown>;
    if (String(item["@type"] ?? "").includes("FcmError")) {
      if (typeof item.errorCode === "string") fcmCode = item.errorCode;
    }
    const violations = Array.isArray(item.fieldViolations)
      ? item.fieldViolations
      : [];
    tokenFieldViolation ||= violations.some((violation) => {
      if (!violation || typeof violation !== "object") return false;
      const field = String((violation as Record<string, unknown>).field ?? "");
      return field === "message.token" || field.startsWith("message.token.");
    });
  }
  return {
    status: typeof record.status === "string" ? record.status : undefined,
    fcmCode,
    tokenFieldViolation,
  };
}

export function classifyFcmError(
  httpStatus: number,
  body: unknown,
): FcmErrorDecision {
  const detail = fcmDetail(body);
  const code = detail.fcmCode ?? detail.status ?? `HTTP_${httpStatus}`;
  if (code === "UNREGISTERED" || code === "SENDER_ID_MISMATCH") {
    return { code, permanent: true, deactivateDevice: true };
  }
  if (code === "INVALID_ARGUMENT") {
    return {
      code,
      permanent: true,
      deactivateDevice: detail.tokenFieldViolation,
    };
  }
  const temporary = httpStatus === 408 || httpStatus === 429 ||
    httpStatus >= 500 ||
    ["INTERNAL", "UNAVAILABLE", "RESOURCE_EXHAUSTED", "DEADLINE_EXCEEDED"]
      .includes(code);
  return { code, permanent: !temporary, deactivateDevice: false };
}

export function classifyThrownError(): FcmErrorDecision {
  return {
    code: "NETWORK_ERROR",
    permanent: false,
    deactivateDevice: false,
  };
}

export function nextRetryAt(
  attemptCount: number,
  now = new Date(),
): Date | null {
  if (attemptCount >= MAX_ATTEMPTS) return null;
  const exponent = Math.max(0, attemptCount - 1);
  const delayMinutes = Math.min(30 * 2 ** exponent, 12 * 60);
  return new Date(now.getTime() + delayMinutes * 60_000);
}

export function processingRecoveryCutoff(now = new Date()): Date {
  return new Date(now.getTime() - PROCESSING_RECOVERY_MINUTES * 60_000);
}

export function retryBlockReason(input: {
  active: boolean;
  currentScheduleVersion: string;
  eventScheduleVersion: string;
  notice: Notice;
  notifyThreeDays: boolean;
  notifyOneDay: boolean;
}): string | null {
  if (!input.active) return "REMINDER_INACTIVE";
  if (input.currentScheduleVersion !== input.eventScheduleVersion) {
    return "SCHEDULE_CHANGED";
  }
  if (input.notice === "three_days" && !input.notifyThreeDays) {
    return "NOTICE_DISABLED";
  }
  if (input.notice === "one_day" && !input.notifyOneDay) {
    return "NOTICE_DISABLED";
  }
  return null;
}

export function requireDeviceQuery<T>(
  devices: T[] | null,
  error: unknown,
): T[] {
  if (error) throw new Error("device_query_failed");
  return devices ?? [];
}

export function filterEnterpriseDevices<
  T extends {
    user_id?: string;
    organization_id?: string;
  },
>(devices: T[], organizationId: string, activeUserIds: Set<string>): T[] {
  return devices.filter((device) =>
    device.organization_id === organizationId && device.user_id != null &&
    activeUserIds.has(device.user_id)
  );
}

export async function mapLimit<T>(
  items: readonly T[],
  concurrency: number,
  worker: (item: T) => Promise<void>,
  onError: (error: unknown) => void,
): Promise<void> {
  let cursor = 0;
  const count = Math.max(1, Math.min(concurrency, items.length));
  await Promise.all(
    Array.from({ length: count }, async () => {
      while (cursor < items.length) {
        const item = items[cursor++];
        try {
          await worker(item);
        } catch (error) {
          onError(error);
        }
      }
    }),
  );
}
