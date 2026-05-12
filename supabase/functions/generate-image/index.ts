// Supabase Edge Function: generate-image
//
// Required env:
//   OPENAI_API_KEY
//
// The iOS app calls this function with the user's Supabase access token.
// The OpenAI key stays server-side and never ships inside the app binary.

const OPENAI_URL = "https://api.openai.com/v1/images/generations";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const auth = req.headers.get("Authorization") || "";
  if (!auth.startsWith("Bearer ")) {
    return json({ error: "not_authenticated" }, 401);
  }
  const user = await verifyUser(auth);
  if (!user?.id) {
    return json({ error: "not_authenticated" }, 401);
  }

  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) {
    return json({ error: "missing_openai_key" }, 500);
  }

  let prompt = "";
  try {
    const body = await req.json();
    prompt = String(body?.prompt || "").trim();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  if (prompt.length < 3) {
    return json({ error: "prompt_required" }, 400);
  }
  if (prompt.length > 900) {
    prompt = prompt.slice(0, 900);
  }

  const finalPrompt = [
    prompt,
    "Create a polished marketing-ready square image.",
    "No explicit sexual content, hate, gore, real-person impersonation, or misleading medical/financial claims.",
    "Premium dark studio composition, clean commercial lighting, high detail."
  ].join("\n");

  const response = await fetch(OPENAI_URL, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-image-1-mini",
      prompt: finalPrompt,
      size: "1024x1024",
      quality: "low",
      n: 1,
    }),
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    return json({
      error: "openai_error",
      status: response.status,
      message: payload?.error?.message || "Image generation failed",
    }, 502);
  }

  const imageBase64 = payload?.data?.[0]?.b64_json;
  if (!imageBase64) {
    return json({ error: "missing_image" }, 502);
  }

  return json({
    imageBase64,
    prompt,
  }, 200);
});

async function verifyUser(authorization: string): Promise<{ id: string } | null> {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !anonKey) return null;

  const res = await fetch(`${supabaseUrl}/auth/v1/user`, {
    headers: {
      "Authorization": authorization,
      "apikey": anonKey,
    },
  });
  if (!res.ok) return null;
  return await res.json().catch(() => null);
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}
