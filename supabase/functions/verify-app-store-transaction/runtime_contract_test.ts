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
    "the verified purchase runtime is not using the pinned Apple roots",
  );
  assertNotMatch(
    source,
    /APPLE_ROOT_CA_CERTS_(?:PEM|BASE64)/,
    "the verified purchase runtime still depends on mutable root secrets",
  );
});

Deno.test("production verifier uses the source-pinned App Store app id", () => {
  assertMatch(
    source,
    /APP_APPLE_ID/,
    "the verified purchase runtime is not using the pinned App Store app id",
  );
  assertNotMatch(
    source,
    /Deno\.env\.get\("APPLE_APP_ID"\)/,
    "the verified purchase runtime still depends on a mutable App Store app-id secret",
  );
});

Deno.test("runtime verifies ES256 directly without Edge-incompatible key export", () => {
  assertMatch(
    edgeVerifierSource,
    /verifySignature\(/,
    "the verified purchase runtime is not using direct ES256 verification",
  );
  assertNotMatch(
    edgeVerifierSource,
    /publicKey\.export\(/,
    "the verified purchase runtime still uses Edge-incompatible public-key export",
  );
  assertMatch(
    edgeVerifierSource,
    /alg !== "ES256"/,
    "the verified purchase runtime does not require Apple's ES256 algorithm",
  );
  assertMatch(
    edgeVerifierSource,
    /verifyCertificateChain\(/,
    "the verified purchase runtime bypasses Apple's certificate-chain validation",
  );
  assertMatch(
    edgeVerifierSource,
    /dsaEncoding: "ieee-p1363"/,
    "the verified purchase runtime does not verify the JWS P1363 signature format",
  );
  assertMatch(
    edgeVerifierSource,
    /asymmetricKeyType !== "ec"/,
    "the verified purchase runtime does not require an EC leaf key",
  );
  assertMatch(
    edgeVerifierSource,
    /"prime256v1", "secp256r1", "P-256"/,
    "the verified purchase runtime does not require the P-256 curve",
  );
  assertMatch(
    edgeVerifierSource,
    /signature\.length !== 64/,
    "the verified purchase runtime does not require a 64-byte ES256 signature",
  );
});
