export type AppStoreEnvironment = "Production" | "Sandbox";

export const APP_BUNDLE_ID = "com.x5studio.app";
export const VERIFIED_MONTHLY_PRODUCT_ID = "com.x5studio.app.verified.monthly";
export const CONSUMABLE_PRODUCT_IDS = new Set([
  "com.x5studio.app.credits.1000",
  "com.x5studio.app.credits.2000",
  "com.x5studio.app.credits.5000",
]);

const MAX_SIGNED_PAYLOAD_LENGTH = 128 * 1024;
const MAX_CLOCK_SKEW_MS = 5 * 60_000;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export class InputError extends Error {
  constructor(readonly code: string, readonly status = 400) {
    super(code);
  }
}

export interface RefundNotificationEvent {
  eventId: string;
  notificationType: "REFUND" | "REFUND_REVERSED";
  userId: string;
  productKind: "consumable" | "subscription";
  productId: string;
  environment: AppStoreEnvironment;
  transactionId: string;
  originalTransactionId: string;
  appAccountToken: string;
  purchaseDate: string;
  expiresDate: string | null;
  transactionSignedDate: string;
  notificationSignedDate: string;
  revocationDate: string | null;
  revocationPercentage: number | null;
  quantity: number | null;
}

export function parseNotificationRequestBody(_body: unknown): string {
  if (!isRecord(_body) || Array.isArray(_body)) {
    throw new InputError("invalid_request_body");
  }
  const keys = Object.keys(_body);
  if (keys.length !== 1 || keys[0] !== "signedPayload") {
    throw new InputError("invalid_request_body");
  }
  if (typeof _body.signedPayload !== "string") {
    throw new InputError("invalid_signed_payload");
  }
  const value = _body.signedPayload.trim();
  if (!value || value.length > MAX_SIGNED_PAYLOAD_LENGTH) {
    throw new InputError("invalid_signed_payload");
  }
  return value;
}

export function parseUntrustedNotificationEnvironment(
  _signedPayload: string,
): AppStoreEnvironment {
  const segments = _signedPayload.split(".");
  if (
    segments.length !== 3 || segments.some((segment) => segment.length === 0)
  ) {
    throw new InputError("invalid_signed_payload");
  }

  let payload: unknown;
  try {
    payload = JSON.parse(
      new TextDecoder().decode(decodeBase64URL(segments[1])),
    );
  } catch {
    throw new InputError("invalid_signed_payload");
  }
  if (!isRecord(payload)) {
    throw new InputError("invalid_signed_payload");
  }
  const carriers = [payload.data, payload.summary, payload.appData]
    .filter((value) => isRecord(value));
  if (carriers.length !== 1) {
    throw new InputError("invalid_environment");
  }
  const environment = carriers[0].environment;
  if (environment === "Production" || environment === "Sandbox") {
    return environment;
  }
  throw new InputError("invalid_environment");
}

export function validateVerifiedRefundNotification(
  _notification: unknown,
  _transaction: unknown,
  _expectedEnvironment: AppStoreEnvironment,
  _nowMs: number,
): RefundNotificationEvent {
  if (!isRecord(_notification) || !isRecord(_notification.data)) {
    throw new InputError("invalid_notification_payload");
  }
  if (!isRecord(_transaction)) {
    throw new InputError("invalid_transaction_payload");
  }

  const notificationType = _notification.notificationType;
  if (
    notificationType !== "REFUND" && notificationType !== "REFUND_REVERSED"
  ) {
    throw new InputError("unsupported_notification_type", 200);
  }
  const eventId = requiredUUID(
    _notification.notificationUUID,
    "invalid_notification_uuid",
  );
  const version = requiredString(
    _notification.version,
    "invalid_notification_version",
    16,
  );
  if (!version.startsWith("2.")) {
    throw new InputError("invalid_notification_version");
  }

  if (
    _notification.data.bundleId !== APP_BUNDLE_ID ||
    _transaction.bundleId !== APP_BUNDLE_ID
  ) {
    throw new InputError("invalid_bundle");
  }
  if (
    _notification.data.environment !== _expectedEnvironment ||
    _transaction.environment !== _expectedEnvironment
  ) {
    throw new InputError("invalid_environment");
  }
  requiredString(
    _notification.data.signedTransactionInfo,
    "missing_signed_transaction_info",
    MAX_SIGNED_PAYLOAD_LENGTH,
  );

  const productId = requiredString(
    _transaction.productId,
    "unsupported_product",
  );
  const productKind = CONSUMABLE_PRODUCT_IDS.has(productId)
    ? "consumable"
    : productId === VERIFIED_MONTHLY_PRODUCT_ID
    ? "subscription"
    : null;
  if (!productKind) throw new InputError("unsupported_product", 200);

  const transactionId = requiredString(
    _transaction.transactionId,
    "invalid_transaction_id",
    255,
  );
  const originalTransactionId = requiredString(
    _transaction.originalTransactionId,
    "invalid_original_transaction_id",
    255,
  );
  const appAccountToken = requiredUUID(
    _transaction.appAccountToken,
    _transaction.appAccountToken === undefined ||
      _transaction.appAccountToken === null
      ? "missing_account_token"
      : "invalid_app_account_token",
  ).toLowerCase();

  if (productKind === "consumable") {
    if (_transaction.type !== "Consumable") {
      throw new InputError("invalid_product_type");
    }
    if (_transaction.quantity !== 1) {
      throw new InputError("invalid_quantity");
    }
    if (
      _transaction.expiresDate !== undefined &&
      _transaction.expiresDate !== null
    ) {
      throw new InputError("invalid_expiration_date");
    }
  } else {
    if (_transaction.type !== "Auto-Renewable Subscription") {
      throw new InputError("invalid_product_type");
    }
    if (_transaction.quantity !== undefined && _transaction.quantity !== null) {
      throw new InputError("invalid_quantity");
    }
  }

  const purchaseDateMs = requiredTimestamp(
    _transaction.purchaseDate,
    "invalid_purchase_date",
  );
  const transactionSignedDateMs = requiredTimestamp(
    _transaction.signedDate,
    "invalid_signed_date",
  );
  const notificationSignedDateMs = requiredTimestamp(
    _notification.signedDate,
    "invalid_notification_signed_date",
  );
  for (
    const [value, code] of [
      [purchaseDateMs, "invalid_purchase_date"],
      [transactionSignedDateMs, "invalid_signed_date"],
      [notificationSignedDateMs, "invalid_notification_signed_date"],
    ] as const
  ) {
    if (value > _nowMs + MAX_CLOCK_SKEW_MS) throw new InputError(code);
  }
  if (
    transactionSignedDateMs < purchaseDateMs - MAX_CLOCK_SKEW_MS ||
    notificationSignedDateMs < transactionSignedDateMs - MAX_CLOCK_SKEW_MS
  ) {
    throw new InputError("invalid_signed_date");
  }

  let expiresDate: string | null = null;
  if (productKind === "subscription") {
    const expiresDateMs = requiredTimestamp(
      _transaction.expiresDate,
      "invalid_expiration_date",
    );
    if (expiresDateMs <= purchaseDateMs) {
      throw new InputError("invalid_expiration_date");
    }
    expiresDate = new Date(expiresDateMs).toISOString();
  }

  let normalizedRevocationDate: string | null = null;
  let normalizedRevocationPercentage: number | null = null;
  if (notificationType === "REFUND") {
    const revocationDateMs = requiredTimestamp(
      _transaction.revocationDate,
      "invalid_revocation_date",
    );
    if (
      revocationDateMs < purchaseDateMs ||
      revocationDateMs > _nowMs + MAX_CLOCK_SKEW_MS ||
      transactionSignedDateMs < revocationDateMs - MAX_CLOCK_SKEW_MS
    ) {
      throw new InputError("invalid_revocation_date");
    }
    normalizedRevocationDate = new Date(revocationDateMs).toISOString();
    normalizedRevocationPercentage = normalizeRefundPercentage(
      _transaction.revocationType,
      _transaction.revocationPercentage,
    );
  } else {
    if (
      _transaction.revocationDate !== undefined ||
      _transaction.revocationReason !== undefined ||
      _transaction.revocationType !== undefined ||
      _transaction.revocationPercentage !== undefined
    ) {
      throw new InputError("invalid_refund_reversal");
    }
  }

  return {
    eventId,
    notificationType,
    userId: appAccountToken,
    productKind,
    productId,
    environment: _expectedEnvironment,
    transactionId,
    originalTransactionId,
    appAccountToken,
    purchaseDate: new Date(purchaseDateMs).toISOString(),
    expiresDate,
    transactionSignedDate: new Date(transactionSignedDateMs).toISOString(),
    notificationSignedDate: new Date(notificationSignedDateMs).toISOString(),
    revocationDate: normalizedRevocationDate,
    revocationPercentage: normalizedRevocationPercentage,
    quantity: productKind === "consumable" ? 1 : null,
  };
}

export function parseAppleRootCertificates(
  pem: string | undefined,
  base64: string | undefined,
): Uint8Array[] {
  const certificates: Uint8Array[] = [];

  if (pem?.trim()) {
    const matches = [
      ...pem.matchAll(
        /-----BEGIN CERTIFICATE-----([\s\S]*?)-----END CERTIFICATE-----/g,
      ),
    ];
    if (matches.length === 0) {
      throw new InputError("invalid_apple_root_certificates", 500);
    }
    for (const match of matches) {
      certificates.push(decodeCertificateBase64(match[1]));
    }
  }

  if (base64?.trim()) {
    let encodedCertificates: unknown;
    try {
      encodedCertificates = JSON.parse(base64);
    } catch {
      throw new InputError("invalid_apple_root_certificates", 500);
    }
    if (
      !Array.isArray(encodedCertificates) ||
      encodedCertificates.length === 0
    ) {
      throw new InputError("invalid_apple_root_certificates", 500);
    }
    for (const encoded of encodedCertificates) {
      if (typeof encoded !== "string") {
        throw new InputError("invalid_apple_root_certificates", 500);
      }
      certificates.push(decodeCertificateBase64(encoded));
    }
  }

  if (certificates.length === 0) {
    throw new InputError("missing_apple_root_certificates", 500);
  }
  if (certificates.length > 10) {
    throw new InputError("invalid_apple_root_certificates", 500);
  }
  return certificates;
}

export function parseAppAppleId(raw: string | undefined): number {
  if (!raw?.trim()) throw new InputError("missing_apple_app_id", 500);
  if (!/^\d+$/.test(raw.trim())) {
    throw new InputError("invalid_apple_app_id", 500);
  }
  const parsed = Number(raw.trim());
  if (!Number.isSafeInteger(parsed) || parsed <= 0) {
    throw new InputError("invalid_apple_app_id", 500);
  }
  return parsed;
}

function normalizeRefundPercentage(
  revocationType: unknown,
  percentage: unknown,
): number {
  if (
    percentage !== undefined &&
    (typeof percentage !== "number" ||
      !Number.isSafeInteger(percentage) ||
      percentage <= 0 ||
      percentage > 100000)
  ) {
    throw new InputError("invalid_revocation_percentage");
  }

  if (revocationType === undefined || revocationType === null) {
    return percentage === undefined ? 100000 : percentage as number;
  }
  if (revocationType === "REFUND_FULL") {
    if (percentage !== undefined && percentage !== 100000) {
      throw new InputError("invalid_revocation_percentage");
    }
    return 100000;
  }
  if (revocationType === "REFUND_PRORATED") {
    if (
      typeof percentage !== "number" || percentage <= 0 || percentage >= 100000
    ) {
      throw new InputError("invalid_revocation_percentage");
    }
    return percentage;
  }
  throw new InputError("invalid_revocation_percentage");
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function requiredString(value: unknown, code: string, max = 128): string {
  if (typeof value !== "string") throw new InputError(code);
  const normalized = value.trim();
  if (!normalized || normalized.length > max) throw new InputError(code);
  return normalized;
}

function requiredUUID(value: unknown, code: string): string {
  const normalized = requiredString(value, code);
  if (!UUID_PATTERN.test(normalized)) throw new InputError(code);
  return normalized;
}

function requiredTimestamp(value: unknown, code: string): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value <= 0) {
    throw new InputError(code);
  }
  return value;
}

function decodeBase64URL(value: string): Uint8Array {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) throw new Error("invalid base64url");
  const standard = value.replaceAll("-", "+").replaceAll("_", "/");
  const decoded = atob(
    standard.padEnd(Math.ceil(standard.length / 4) * 4, "="),
  );
  return Uint8Array.from(decoded, (character) => character.charCodeAt(0));
}

function decodeCertificateBase64(value: string): Uint8Array {
  const compact = value.replace(/\s+/g, "");
  if (
    !compact || compact.length % 4 === 1 ||
    !/^[A-Za-z0-9+/]*={0,2}$/.test(compact)
  ) {
    throw new InputError("invalid_apple_root_certificates", 500);
  }
  try {
    const decoded = atob(compact);
    if (!decoded) throw new Error("empty certificate");
    return Uint8Array.from(decoded, (character) => character.charCodeAt(0));
  } catch (error) {
    if (error instanceof InputError) throw error;
    throw new InputError("invalid_apple_root_certificates", 500);
  }
}
