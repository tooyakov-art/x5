const source = await Deno.readTextFile(
  new URL("./index.ts", import.meta.url),
);
const edgeVerifierSource = await Deno.readTextFile(
  new URL("./edge_jws_verifier.ts", import.meta.url),
);

function assertMatch(value: string, pattern: RegExp, message: string): void {
  if (!pattern.test(value)) throw new Error(message);
}

function assertNotMatch(value: string, pattern: RegExp, message: string): void {
  if (pattern.test(value)) throw new Error(message);
}

Deno.test("runtime uses source-pinned official Apple trust roots", () => {
  assertMatch(
    source,
    /pinnedAppleRootCertificates\(\)/,
    "the notification runtime is not using the pinned Apple roots",
  );
  assertNotMatch(
    source,
    /APPLE_ROOT_CA_CERTS_(?:PEM|BASE64)/,
    "the notification runtime still depends on mutable root secrets",
  );
});

Deno.test("production verifier uses the source-pinned App Store app id", () => {
  assertMatch(
    source,
    /APP_APPLE_ID/,
    "the notification runtime is not using the pinned App Store app id",
  );
  assertNotMatch(
    source,
    /Deno\.env\.get\("APPLE_APP_ID"\)/,
    "the notification runtime still depends on a mutable App Store app-id secret",
  );
});

Deno.test("runtime verifies both Apple JWS layers with the pinned Apple library", () => {
  assertMatch(
    source,
    /@apple\/app-store-server-library/,
    "Apple server library import is missing",
  );
  assertMatch(
    source,
    /verifyAndDecodeNotification\(\s*signedPayload,?\s*\)/,
    "outer signedPayload is not verified",
  );
  assertMatch(
    source,
    /verifyAndDecodeTransaction\(\s*signedTransaction,?\s*\)/,
    "inner signedTransactionInfo is not verified",
  );
  assertMatch(
    source,
    /VerificationStatus\.RETRYABLE_VERIFICATION_FAILURE/,
    "retryable Apple verification failures are not classified",
  );
});

Deno.test("runtime avoids live Apple OCSP that is incompatible with the Deno edge runtime", () => {
  assertMatch(
    source,
    /new EdgeCompatibleSignedDataVerifier\([\s\S]*?getAppleRootCertificates\(\),\s*false,\s*environment === "Production"/,
    "Apple verifier must retain signed JWS validation without live OCSP",
  );
});

Deno.test("runtime verifies ES256 directly without Edge-incompatible key export", () => {
  assertMatch(
    edgeVerifierSource,
    /verifySignature\(/,
    "the notification runtime is not using direct ES256 verification",
  );
  assertNotMatch(
    edgeVerifierSource,
    /publicKey\.export\(/,
    "the notification runtime still uses Edge-incompatible public-key export",
  );
  assertMatch(
    edgeVerifierSource,
    /alg !== "ES256"/,
    "the notification runtime does not require Apple's ES256 algorithm",
  );
  assertMatch(
    edgeVerifierSource,
    /verifyCertificateChain\(/,
    "the notification runtime bypasses Apple's certificate-chain validation",
  );
  assertMatch(
    edgeVerifierSource,
    /dsaEncoding: "ieee-p1363"/,
    "the notification runtime does not verify the JWS P1363 signature format",
  );
  assertMatch(
    edgeVerifierSource,
    /asymmetricKeyType !== "ec"/,
    "the notification runtime does not require an EC leaf key",
  );
  assertMatch(
    edgeVerifierSource,
    /"prime256v1", "secp256r1", "P-256"/,
    "the notification runtime does not require the P-256 curve",
  );
  assertMatch(
    edgeVerifierSource,
    /signature\.length !== 64/,
    "the notification runtime does not require a 64-byte ES256 signature",
  );
});

Deno.test("runtime applies only the dedicated service-role notification RPC", () => {
  assertMatch(
    source,
    /apply_verified_app_store_server_notification/,
    "dedicated notification RPC is missing",
  );
  assertMatch(
    source,
    /SUPABASE_SERVICE_ROLE_KEY/,
    "service role key is not used server-side",
  );
  assertMatch(
    source,
    /if \(import\.meta\.main\)[\s\S]*Deno\.serve/,
    "Edge runtime entrypoint is missing",
  );
});
