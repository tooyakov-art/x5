const workflow = await Deno.readTextFile(
  new URL("../../../.github/workflows/ios-course-ci.yml", import.meta.url),
);

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("iOS course CI validates the public App Store notification webhook", () => {
  assert(
    workflow.includes("supabase/functions/app-store-notifications/**"),
    "workflow path filter does not include app-store-notifications",
  );
  assert(
    /working-directory:\s*supabase\/functions\/app-store-notifications[\s\S]*?deno fmt --check[\s\S]*?deno lint[\s\S]*?deno check index\.ts[\s\S]*?deno test --allow-read/i
      .test(workflow),
    "workflow does not run the full app-store-notifications Deno gate",
  );
});
