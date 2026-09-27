// Прокси к Groq: ключ живёт только здесь, в секретах Supabase.
// Деплой:  supabase functions deploy groq-proxy
// Секреты: supabase secrets set GROQ_API_KEY=gsk_... GROQ_MODELS=openai/gpt-oss-120b,llama-3.3-70b-versatile
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const allowed = new Set(
  (Deno.env.get("GROQ_MODELS") ?? "openai/gpt-oss-120b,llama-3.3-70b-versatile").split(",").map((s) => s.trim()),
);

// Лимит на пользователя внутри инстанса: бесплатный Groq ~30 запросов в минуту на весь проект,
// а один вопрос Алану — это 2–4 запроса (инструменты).
const hits = new Map<string, number[]>();
const PER_MINUTE = 12;

function json(body: unknown, status = 200, extra: Record<string, string> = {}) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, ...extra, "Content-Type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, (Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY"))!, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
  });
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return json({ error: "unauthorized" }, 401);

  const now = Date.now();
  const recent = (hits.get(user.id) ?? []).filter((t) => now - t < 60_000);
  if (recent.length >= PER_MINUTE) return json({ error: "rate limited" }, 429, { "retry-after": "20" });
  recent.push(now);
  hits.set(user.id, recent);

  const raw = await req.text();
  if (raw.length > 120_000) return json({ error: "request too large" }, 413);

  let body: Record<string, unknown>;
  try {
    body = JSON.parse(raw);
  } catch {
    return json({ error: "bad json" }, 400);
  }
  const model = String(body.model ?? "");
  if (!allowed.has(model)) return json({ error: `model ${model} is not allowed` }, 400);
  body.stream = false;

  const key = Deno.env.get("GROQ_API_KEY");
  if (!key) return json({ error: "GROQ_API_KEY is not set" }, 500);

  const r = await fetch("https://api.groq.com/openai/v1/chat/completions", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
    body: JSON.stringify(body),
  });
  // Статус и тело пробрасываем как есть: приложение само различает 429, 413 и tool_use_failed.
  const headers: Record<string, string> = { ...cors, "Content-Type": "application/json" };
  const retry = r.headers.get("retry-after");
  if (retry) headers["retry-after"] = retry;
  return new Response(await r.text(), { status: r.status, headers });
});
