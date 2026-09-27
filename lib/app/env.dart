import 'dart:math' as math;

/// Все ключи передаются при сборке через --dart-define, в коде их нет.
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  /// Publishable key (sb_publishable_…) или старый anon key — оба публичные.
  static const supabaseKey = String.fromEnvironment('SUPABASE_KEY');

  /// Ключ Groq только для локальной отладки без Supabase. В сборке для людей
  /// ключ должен жить в Edge Function groq-proxy, иначе его можно извлечь из APK.
  static const groqKeyDevOnly = String.fromEnvironment('GROQ_API_KEY');

  /// Модель задаётся снаружи: список моделей Groq меняется.
  /// openai/gpt-oss-120b есть в бесплатном тарифе и умеет вызывать инструменты.
  static const groqModel = String.fromEnvironment('GROQ_MODEL', defaultValue: 'openai/gpt-oss-120b');

  /// Имя Telegram-бота без @, например AlanMountainBot.
  static const telegramBot = String.fromEnvironment('TELEGRAM_BOT');

  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
  static bool get hasAi => hasSupabase || groqKeyDevOnly.isNotEmpty;
}

/// Весь Казахстан живёт в UTC+5. Время устройства туриста может быть другим,
/// поэтому «сейчас» всегда считаем от UTC.
DateTime almatyNow() {
  final u = DateTime.now().toUtc().add(const Duration(hours: 5));
  return DateTime(u.year, u.month, u.day, u.hour, u.minute, u.second);
}

DateTime almatyToday() {
  final n = almatyNow();
  return DateTime(n.year, n.month, n.day);
}

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Восход и закат по уравнению восхода (NOAA/Wikipedia), в часах Алматы.
/// Используется, когда до даты похода дальше горизонта прогноза.
/// Проверено: 27.09 для Кок-Жайляу — 05:44 / 17:42.
(DateTime sunrise, DateTime sunset) sunTimes(DateTime date, double lat, double lon) {
  double rad(double d) => d * math.pi / 180;
  double deg(double r) => r * 180 / math.pi;

  final unixDays =
      DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch / 86400000;
  final jd = 2440587.5 + unixDays;
  final n = (jd - 2451545.0 + 0.0008).ceilToDouble();
  final jStar = n - lon / 360;
  final m = (357.5291 + 0.98560028 * jStar) % 360;
  final c = 1.9148 * math.sin(rad(m)) + 0.02 * math.sin(rad(2 * m)) + 0.0003 * math.sin(rad(3 * m));
  final lambda = (m + c + 180 + 102.9372) % 360;
  final jTransit = 2451545.0 + jStar + 0.0053 * math.sin(rad(m)) - 0.0069 * math.sin(rad(2 * lambda));
  final sinDelta = math.sin(rad(lambda)) * math.sin(rad(23.4397));
  final cosDelta = math.cos(math.asin(sinDelta));
  final phi = rad(lat);
  final cosW = (math.sin(rad(-0.833)) - math.sin(phi) * sinDelta) / (math.cos(phi) * cosDelta);
  final w = deg(math.acos(cosW.clamp(-1.0, 1.0)));

  DateTime toAlmaty(double j) {
    final u = DateTime.fromMillisecondsSinceEpoch(((j - 2440587.5) * 86400000).round(), isUtc: true)
        .add(const Duration(hours: 5));
    return DateTime(u.year, u.month, u.day, u.hour, u.minute);
  }

  return (toAlmaty(jTransit - w / 360), toAlmaty(jTransit + w / 360));
}
