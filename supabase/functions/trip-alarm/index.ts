// Каждые 5 минут (pg_cron) ищет походы, где контрольное время прошло, а турист не отметился,
// и пишет его близким в Telegram. Деплой: supabase functions deploy trip-alarm --no-verify-jwt
// Секреты: TELEGRAM_BOT_TOKEN, CRON_SECRET
import { createClient } from "npm:@supabase/supabase-js@2";

Deno.serve(async (req) => {
  if (req.headers.get("x-cron-secret") !== Deno.env.get("CRON_SECRET")) {
    return new Response("forbidden", { status: 403 });
  }
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const bot = Deno.env.get("TELEGRAM_BOT_TOKEN")!;

  const { data: overdue, error } = await db
    .from("live_trips")
    .select("*")
    .eq("status", "active")
    .lt("control_at", new Date().toISOString());
  if (error) return new Response(error.message, { status: 500 });

  const time = (iso: string) =>
    new Date(iso).toLocaleString("ru-RU", { timeZone: "Asia/Almaty", hour: "2-digit", minute: "2-digit", day: "2-digit", month: "2-digit" });

  let sent = 0;
  for (const t of overdue ?? []) {
    const { data: contacts } = await db.from("contact_links").select("chat_id").eq("owner", t.owner).not("chat_id", "is", null);
    const lines = [
      `⚠️ ${t.owner_name || "Турист"} не отметился(ась) после похода на «${t.route_name}».`,
      `Контрольное время: ${time(t.control_at)} (Алматы).`,
      t.last_lat != null
        ? `Последняя точка: ${t.last_lat.toFixed(5)}, ${t.last_lon.toFixed(5)} (±${Math.round(t.last_acc ?? 0)} м) в ${time(t.last_at)}.\nКарта: https://www.openstreetmap.org/?mlat=${t.last_lat}&mlon=${t.last_lon}#map=15/${t.last_lat}/${t.last_lon}`
        : "Координаты с телефона не поступали.",
      t.last_battery != null ? `Заряд телефона тогда: ${t.last_battery}%.` : "",
      t.owner_phone ? `Попробуйте дозвониться: ${t.owner_phone}.` : "Попробуйте дозвониться.",
      "Если не отвечает — звоните 112 и передайте эти данные.",
    ].filter(Boolean);
    for (const c of contacts ?? []) {
      await fetch(`https://api.telegram.org/bot${bot}/sendMessage`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ chat_id: c.chat_id, text: lines.join("\n") }),
      });
      sent++;
    }
    await db.from("live_trips").update({ status: "alerted" }).eq("id", t.id);
  }
  return Response.json({ overdue: overdue?.length ?? 0, sent });
});
