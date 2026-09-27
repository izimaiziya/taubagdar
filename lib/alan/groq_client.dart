import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/env.dart';

/// ИИ недоступен: нет ключа, нет сети, сервер ответил ошибкой.
class AiUnavailable implements Exception {
  final String reason;
  AiUnavailable(this.reason);
  @override
  String toString() => reason;
}

/// Исчерпан лимит бесплатного тарифа Groq (HTTP 429).
class AiRateLimited implements Exception {
  final Duration? retryAfter;
  AiRateLimited([this.retryAfter]);
}

/// Модель сгенерировала некорректный вызов инструмента (Groq: 400 tool_use_failed).
class AiToolUseFailed implements Exception {}

/// Запрос не помещается в лимит токенов в минуту (Groq: 413).
class AiTooLarge implements Exception {}

/// Клиент Groq (OpenAI-совместимый /chat/completions).
/// С Supabase — через Edge Function groq-proxy, ключ хранится на сервере.
/// Без Supabase — напрямую с ключом из --dart-define (только для демо).
class GroqClient {
  static const _endpoint = 'https://api.groq.com/openai/v1/chat/completions';

  Future<Map<String, dynamic>> chat(Map<String, dynamic> body) async {
    if (Env.hasSupabase) return _viaProxy(body);
    if (Env.groqKeyDevOnly.isNotEmpty) return _direct(body);
    throw AiUnavailable('ИИ не подключён.');
  }

  Future<Map<String, dynamic>> _direct(Map<String, dynamic> body) async {
    http.Response r;
    try {
      r = await http
          .post(Uri.parse(_endpoint),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ${Env.groqKeyDevOnly}',
              },
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 40));
    } catch (_) {
      throw AiUnavailable('Нет связи с Groq.');
    }
    final text = utf8.decode(r.bodyBytes);
    _throwOnError(r.statusCode, text, r.headers['retry-after']);
    return jsonDecode(text) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _viaProxy(Map<String, dynamic> body) async {
    try {
      final res = await Supabase.instance.client.functions
          .invoke('groq-proxy', body: body)
          .timeout(const Duration(seconds: 45));
      final data = res.data is String ? jsonDecode(res.data as String) : res.data;
      return Map<String, dynamic>.from(data as Map);
    } on FunctionException catch (e) {
      final details = e.details is String ? e.details as String : jsonEncode(e.details);
      _throwOnError(e.status, details, null);
      throw AiUnavailable('Сервер Алана ответил ошибкой ${e.status}.');
    } on AiRateLimited {
      rethrow;
    } catch (e) {
      if (e is AiToolUseFailed || e is AiTooLarge || e is AiUnavailable) rethrow;
      throw AiUnavailable('Нет связи с сервером Алана.');
    }
  }

  static void _throwOnError(int status, String body, String? retryAfter) {
    if (status == 200) return;
    if (status == 429) {
      final s = double.tryParse(retryAfter ?? '');
      throw AiRateLimited(s == null ? null : Duration(milliseconds: (s * 1000).round()));
    }
    if (status == 413) throw AiTooLarge();
    if (status == 400 && body.contains('tool_use_failed')) throw AiToolUseFailed();
    throw AiUnavailable('Groq ответил $status.');
  }
}
