import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Отправка без share_plus: SMS-приложение и окно «Поделиться» Telegram
/// открываются через url_launcher. Текст всегда копируется в буфер —
/// его можно вставить в любой мессенджер, если нужного приложения нет.

/// Открывает SMS с готовым текстом для одного или нескольких номеров.
Future<bool> sendSms(List<String> phones, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  final to = phones.where((p) => p.trim().isNotEmpty).join(';');
  final uri = Uri.parse('sms:$to?body=${Uri.encodeComponent(text)}');
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Открывает окно «Поделиться» Telegram со ссылкой и текстом.
Future<bool> shareToTelegram(String link, String text) async {
  await Clipboard.setData(ClipboardData(text: '$text $link'));
  final uri = Uri.parse(
      'https://t.me/share/url?url=${Uri.encodeComponent(link)}&text=${Uri.encodeComponent(text)}');
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
