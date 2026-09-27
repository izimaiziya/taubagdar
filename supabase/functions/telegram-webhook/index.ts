// Привязка экстренного контакта: человек открывает t.me/<бот>?start=<token> и жмёт Start.
// Деплой: supabase functions deploy telegram-webhook --no-verify-jwt
// Секреты: TELEGRAM_BOT_TOKEN, TELEGRAM_WEBHOOK_SECRET
// Регистрация вебхука (один раз):
// https://api.telegram.org/bot<TOKEN>/setWebhook?url=https://<PROJECT_REF>.supabase.co/functions/v1/telegram-webhook&secret_token=<TELEGRAM_WEBHOOK_SECRET>
import { createClient } from "npm:@supabase/supabase-js@2";

Deno.serve(async (req) => {
  if (req.headers.get("x-telegram-bot-api-secret-token") !== Deno.env.get("TELEGRAM_WEBHOOK_SECRET")) {
    return new Response("forbidden", { status: 403 });
  }
  const update = await req.json().catch(() => null);
  const msg = update?.message;
  const text: string = msg?.text ?? "";
  if (!msg || !text.startsWith("/start")) return new Response("ok");

  const bot = Deno.env.get("TELEGRAM_BOT_TOKEN")!;
  const reply = (t: string) =>
    fetch(`https://api.telegram.org/bot${bot}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ chat_id: msg.chat.id, text: t }),
    });

  const token = text.split(" ")[1]?.trim();
  if (!token) {
    await reply("Это бот TauBağdar. Откройте ссылку-приглашение, которую вам прислали.");
    return new Response("ok");
  }

  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data } = await db
    .from("contact_links")
    .update({ chat_id: msg.chat.id, linked_at: new Date().toISOString() })
    .eq("token", token)
    .select("owner_name")
    .maybeSingle();

  await reply(
    data
      ? `Готово! Вы экстренный контакт для ${data.owner_name || "туриста"}. Если человек не вернётся из похода вовремя, я напишу вам сюда его последнюю точку.`
      : "Ссылка не найдена. Попросите прислать приглашение ещё раз.",
  );
  return new Response("ok");
});
