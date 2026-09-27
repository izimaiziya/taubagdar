import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../app/env.dart';
import '../core/iter.dart';
import '../data/models.dart';
import '../data/stores.dart';
import '../data/weather_service.dart';
import 'alan_mood.dart';
import 'groq_client.dart';
import 'planner.dart';
import 'safety_content.dart';

// ─────────────────────────── Карточки в чате ───────────────────────────

sealed class AlanCard {
  const AlanCard();
}

class RoutesCard extends AlanCard {
  final List<RouteInfo> routes;
  const RoutesCard(this.routes);
}

class WeatherCard extends AlanCard {
  final RouteInfo route;
  final DayWeather day;
  final WeatherReport? report; // прогноз по высотам; null — если это средние прошлых лет
  const WeatherCard(this.route, this.day, [this.report]);
}

class PlanCard extends AlanCard {
  final RouteInfo route;
  final DayPlan plan;
  final DayWeather day;
  const PlanCard(this.route, this.plan, this.day);
}

class ChecklistCard extends AlanCard {
  final RouteInfo route;
  final List<ChecklistItem> items;
  const ChecklistCard(this.route, this.items);
}

class SafetyCard extends AlanCard {
  final SafetyTopic topic;
  const SafetyCard(this.topic);
}

class ChatMessage {
  final bool fromAlan;
  final String text;
  final List<AlanCard> cards;
  final MascotMood mood;
  const ChatMessage({required this.fromAlan, required this.text, this.cards = const [], this.mood = MascotMood.happy});
}

class ChatState {
  final List<ChatMessage> messages;
  final bool thinking;
  const ChatState({this.messages = const [], this.thinking = false});
  ChatState copyWith({List<ChatMessage>? messages, bool? thinking}) =>
      ChatState(messages: messages ?? this.messages, thinking: thinking ?? this.thinking);
}

// ─────────────────────────── Инструменты ───────────────────────────
// Описания короткие: на бесплатном тарифе Groq лимит ~8 тыс. токенов в минуту,
// а описания инструментов уходят в каждом запросе.

Map<String, dynamic> _fn(String name, String description, Map<String, dynamic> props, [List<String> required = const []]) => {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': {
          'type': 'object',
          'properties': props,
          if (required.isNotEmpty) 'required': required,
        },
      },
    };

const _routeId = {'type': 'string', 'description': 'id маршрута из search_routes'};
const _date = {'type': 'string', 'description': 'Дата YYYY-MM-DD'};

final _toolSchemas = [
  _fn('search_routes', 'Подобрать маршруты под уровень пользователя. Предлагай только маршруты из результата.', {
    'max_hours': {'type': 'number', 'description': 'Сколько часов есть на поход'},
    'with_kids': {'type': 'boolean', 'description': 'Идут ли дети'},
  }),
  _fn('get_route_info', 'Как добраться, риски, оплата входа.', {'route_id': _routeId}, ['route_id']),
  _fn('get_weather', 'Погода наверху маршрута на дату. Вызывай всегда, когда речь о погоде.',
      {'route_id': _routeId, 'date': _date}, ['route_id', 'date']),
  _fn('get_day_plan', 'План дня: старт, время разворота, возвращение, закат.', {'route_id': _routeId, 'date': _date},
      ['route_id', 'date']),
  _fn('get_checklist', 'Список вещей с учётом погоды и снаряжения.', {'route_id': _routeId, 'date': _date},
      ['route_id', 'date']),
  _fn('get_safety_info', 'Проверенные инструкции по безопасности.', {
    'topic': {
      'type': 'string',
      'enum': ['emergency', 'lost', 'cold', 'altitude', 'injury', 'ticks', 'storm', 'notify'],
    },
  }, ['topic']),
];

class ToolOutput {
  final Map<String, dynamic> result;
  final AlanCard? card;
  const ToolOutput(this.result, [this.card]);
}

class ToolError implements Exception {
  final String message;
  ToolError(this.message);
}

class AlanTools {
  AlanTools(this.ref);
  final Ref ref;

  Future<List<RouteInfo>> _routes() => ref.read(routesProvider.future);
  Planner get _planner => Planner(ref.read(profileProvider));

  Future<ToolOutput> run(String name, Map<String, dynamic> args) async {
    try {
      switch (name) {
        case 'search_routes':
          return await _search(args);
        case 'get_route_info':
          return await _info(args);
        case 'get_weather':
          return await _weather(args);
        case 'get_day_plan':
          return await _plan(args);
        case 'get_checklist':
          return await _checklist(args);
        case 'get_safety_info':
          return _safety(args);
        default:
          return ToolOutput({'error': 'Неизвестный инструмент $name'});
      }
    } on WeatherError catch (e) {
      return ToolOutput({'error': e.message});
    } on ToolError catch (e) {
      return ToolOutput({'error': e.message});
    }
  }

  Future<ToolOutput> _search(Map<String, dynamic> args) async {
    final all = await _routes();
    final (fit, rejected) =
        _planner.searchRoutes(all, maxHours: _asDouble(args['max_hours']), withKids: _asBool(args['with_kids']));
    return ToolOutput({
      'suitable': [
        for (final r in fit) {'id': r.id, 'name': r.name, 'difficulty': r.difficultyTitle, 'hours': r.hoursText}
      ],
      'not_suitable': {
        for (final e in rejected.entries) all.firstWhere((r) => r.id == e.key).name: e.value,
      },
    }, fit.isEmpty ? null : RoutesCard(fit));
  }

  Future<ToolOutput> _info(Map<String, dynamic> args) async {
    final r = await _route(args['route_id']);
    return ToolOutput({
      'name': r.name,
      'difficulty': r.difficultyTitle,
      'hours': r.hoursText,
      'max_ele_m': r.maxEleM,
      'how_to_get': r.howToGet,
      'risks': r.risks,
      'fee': r.feeNote,
      'plannable': r.plannable,
      if (!r.plannable) 'why_not_plannable': 'данные маршрута ещё проверяются',
    });
  }

  Future<ToolOutput> _weather(Map<String, dynamic> args) async {
    final r = await _route(args['route_id'], needPlannable: true);
    final date = _parseDate(args['date']);
    final wx = ref.read(weatherServiceProvider);
    final day = await wx.dayFor(r, date);
    WeatherReport? report;
    if (!day.typical) {
      try {
        report = await wx.forecast(r);
      } catch (_) {}
    }
    final json = _dayJson(day);
    if (report != null) {
      json['levels'] = [
        for (final l in report.levels)
          if (l.day(date) != null)
            {
              'level': l.label,
              'elevation_m': l.elevation.isNaN ? null : l.elevation.round(),
              't_min_c': l.day(date)!.tMin.round(),
              't_max_c': l.day(date)!.tMax.round(),
              'gust_max_kmh': l.day(date)!.gustMax.round(),
              'verdict': l.day(date)!.verdict.name,
            }
      ];
    }
    return ToolOutput(json, WeatherCard(r, day, report));
  }

  Future<ToolOutput> _checklist(Map<String, dynamic> args) async {
    final r = await _route(args['route_id'], needPlannable: true);
    final day = await ref.read(weatherServiceProvider).dayFor(r, _parseDate(args['date']));
    final items = _planner.checklist(r, day);
    return ToolOutput({
      'critical': items.where((i) => i.critical).map((i) => i.title).toList(),
      'other': items.where((i) => !i.critical).map((i) => i.title).toList(),
      'to_buy_or_rent': items.where((i) => !i.owned).map((i) => i.title).toList(),
    }, ChecklistCard(r, items));
  }

  ToolOutput _safety(Map<String, dynamic> args) {
    final t = safetyById('${args['topic']}');
    if (t == null) return const ToolOutput({'error': 'Такой темы нет.'});
    return ToolOutput({'title': t.title, 'lead': t.lead, 'steps': t.steps}, SafetyCard(t));
  }

  Future<ToolOutput> _plan(Map<String, dynamic> args) async {
    final r = await _route(args['route_id'], needPlannable: true);
    final day = await ref.read(weatherServiceProvider).dayFor(r, _parseDate(args['date']));
    final plan = _planner.dayPlan(r, day);
    return ToolOutput({
      'start': hhmm(plan.start),
      'turnaround_latest': hhmm(plan.turnaround),
      'return_by': hhmm(plan.returnBy),
      'sunset': hhmm(plan.sunset),
      'limited_by': plan.limitingFactor,
      'feasible': plan.feasible,
      'notes': plan.notes,
    }, PlanCard(r, plan, day));
  }

  /// Модель может передать id маршрута с опечаткой или его название — ищем мягко.
  Future<RouteInfo> _route(dynamic raw, {bool needPlannable = false}) async {
    final q = '${raw ?? ''}'.trim().toLowerCase();
    final all = await _routes();
    final r = all.where((x) => x.id == q).firstOrNone ??
        all.where((x) => x.name.toLowerCase() == q).firstOrNone ??
        all.where((x) => q.isNotEmpty && (x.name.toLowerCase().contains(q) || q.contains(x.id))).firstOrNone;
    if (r == null) throw ToolError('Маршрута "$raw" нет в каталоге. Вызови search_routes и используй id оттуда.');
    if (needPlannable && !r.plannable) {
      throw ToolError('Маршрут "${r.name}" пока нельзя планировать: его данные ещё проверяются.');
    }
    return r;
  }

  DateTime _parseDate(dynamic v) {
    final d = DateTime.tryParse('${v ?? ''}'.trim());
    if (d == null) throw ToolError('Дата должна быть в формате YYYY-MM-DD.');
    return DateTime(d.year, d.month, d.day);
  }

  // Модели иногда присылают числа и булевы значения строками.
  static double? _asDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}'.replaceAll(',', '.'));
  static bool _asBool(dynamic v) => v == true || '$v'.toLowerCase() == 'true';

  Map<String, dynamic> _dayJson(DayWeather d) => {
        'date': isoDate(d.date),
        'kind': d.typical ? 'typical_last_10_years' : 'forecast',
        'summary': weatherText(d.code),
        't_min_c': d.tMin.isNaN ? null : d.tMin.round(),
        't_max_c': d.tMax.isNaN ? null : d.tMax.round(),
        'precip_mm': double.parse(d.precipSum.toStringAsFixed(1)),
        'gust_max_kmh': d.gustMax.round(),
        'sunset': hhmm(d.sunset),
        'verdict': d.verdict.name,
        'warnings': d.warnings,
        if (d.hours.isNotEmpty)
          'by_3_hours': [
            for (final h in d.hours.where((h) => h.time.hour >= 6 && h.time.hour <= 21 && h.time.hour % 3 == 0))
              '${hhmm(h.time)} ${h.tempC.round()}° ${weatherText(h.code)}, порывы ${h.gustKmh.round()}'
          ],
      };
}

// ─────────────────────────── Чат ───────────────────────────

class ChatNotifier extends Notifier<ChatState> {
  final _groq = GroqClient();
  late final AlanTools _tools = AlanTools(ref);

  /// Короткая история для модели: только реплики пользователя и итоговые ответы.
  /// Вызовы инструментов живут внутри одного хода и не копятся — это экономит токены.
  final _history = <Map<String, dynamic>>[];
  static const _historyLimit = 8;

  @override
  ChatState build() => const ChatState(messages: [
        ChatMessage(
          fromAlan: true,
          text: 'Я здесь. Спроси, куда пойти, какая будет погода или что взять с собой.',
        ),
      ]);

  Future<void> send(String text) async {
    final t = text.trim();
    if (t.isEmpty || state.thinking) return;
    state = state.copyWith(messages: [...state.messages, ChatMessage(fromAlan: false, text: t)], thinking: true);

    ChatMessage reply;
    try {
      reply = Env.hasAi ? await _askGroq(t) : await _offline(t);
    } on AiRateLimited {
      reply = await _offline(t, prefix: 'Бесплатный лимит ИИ на минуту закончился, пока отвечу сам.');
    } on AiUnavailable {
      reply = await _offline(t, prefix: 'Сейчас я без связи с ИИ, но главное знаю и так.');
    } on AiToolUseFailed {
      reply = await _offline(t, prefix: 'ИИ запутался с ответом, поэтому отвечу сам.');
    } on AiTooLarge {
      _history.clear();
      reply = await _offline(t, prefix: 'Разговор получился длинным, я начал его с чистого листа.');
    } catch (_) {
      reply = await _offline(t, prefix: 'Что-то пошло не так, отвечу без ИИ.');
    }
    state = state.copyWith(messages: [...state.messages, reply], thinking: false);
  }

  String _system() {
    final p = ref.read(profileProvider);
    final now = almatyNow();
    final weekday = DateFormat('EEEE', 'ru').format(now);
    final exp = ['никогда не ходил в горы', 'ходил по простым тропам', 'ходит регулярно', 'есть альпинистский опыт'][p.expLevel];
    final company = switch (p.company) {
      Company.solo => 'обычно ходит один',
      Company.friends => 'ходит с друзьями',
      Company.family => 'ходит с семьёй и детьми',
      Company.guide => 'ходит с гидом',
      null => 'не указал, с кем ходит',
    };
    // Телефон, email и здоровье в ИИ не отправляем.
    return '''
Ты — Алан, снежный барс и горный напарник в приложении TauBağdar (горы над Алматы).
Сегодня $weekday, ${isoDate(now)}, ${hhmm(now)} по Алматы.
Пользователь: ${p.name.isEmpty ? 'турист' : p.name}, ${p.levelTitle.toLowerCase()}: $exp, $company.

Правила:
- Цифры о погоде, времени, маршрутах и вещах бери только из инструментов. Не придумывай.
- Маршруты — только из search_routes. Если id маршрута неизвестен, сначала вызови search_routes.
- Если человек хочет в поход: вызови get_weather, затем get_day_plan, затем get_checklist.
- «В субботу», «завтра» переводи в дату YYYY-MM-DD от сегодняшней.
- Если инструмент вернул error, объясни это просто.
- Не называй телефоны, цены и правила, которых нет в данных. Экстренный номер — 112.
- Отвечай по-русски, тепло и коротко: 2–4 предложения, без списков и markdown. Подробности пользователь видит в карточках.
- Вызывай инструменты только через механизм tools, никогда не пиши вызовы текстом.''';
  }

  Map<String, dynamic> _request(List<Map<String, dynamic>> messages, {double temperature = 0.3}) => {
        'model': Env.groqModel,
        'messages': [
          {'role': 'system', 'content': _system()},
          ...messages,
        ],
        'tools': _toolSchemas,
        'tool_choice': 'auto',
        'temperature': temperature,
        'max_completion_tokens': 1024,
        // У reasoning-моделей (gpt-oss) меньше рассуждений = быстрее и меньше токенов.
        if (Env.groqModel.startsWith('openai/gpt-oss')) 'reasoning_effort': 'low',
      };

  Future<ChatMessage> _askGroq(String text) async {
    final turn = <Map<String, dynamic>>[
      {'role': 'user', 'content': text},
    ];
    final cards = <AlanCard>[];
    var toolRetryUsed = false;

    for (var step = 0; step < 6; step++) {
      Map<String, dynamic> res;
      try {
        res = await _call([..._history, ...turn], temperature: toolRetryUsed ? 0 : 0.3);
      } on AiToolUseFailed {
        // Groq отклоняет кривой вызов инструмента. Одна повторная попытка с temperature 0.
        if (toolRetryUsed) rethrow;
        toolRetryUsed = true;
        continue;
      }

      final choices = res['choices'] as List?;
      if (choices == null || choices.isEmpty) throw AiUnavailable('Пустой ответ');
      final msg = Map<String, dynamic>.from(choices.first['message'] as Map);
      final calls = (msg['tool_calls'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final content = '${msg['content'] ?? ''}'.trim();

      if (calls.isEmpty) {
        final answer = content.isEmpty ? 'Вот что я нашёл.' : content;
        _remember(text, answer);
        return ChatMessage(fromAlan: true, text: answer, cards: cards, mood: _moodFor(cards));
      }

      // Возвращаем модели только то, что нужно: без поля reasoning.
      turn.add({
        'role': 'assistant',
        if (content.isNotEmpty) 'content': content,
        'tool_calls': [
          for (final c in calls)
            {
              'id': c['id'],
              'type': 'function',
              'function': {
                'name': (c['function'] as Map)['name'],
                'arguments': _argsString((c['function'] as Map)['arguments']),
              },
            }
        ],
      });

      for (final c in calls) {
        final fn = Map<String, dynamic>.from(c['function'] as Map);
        final name = '${fn['name']}';
        final out = await _tools.run(name, _parseArgs(fn['arguments']));
        if (out.card != null) cards.add(out.card!);
        turn.add({'role': 'tool', 'tool_call_id': c['id'], 'name': name, 'content': jsonEncode(out.result)});
      }
    }

    const fallback = 'Я немного запутался. Спроси ещё раз, чуть проще.';
    _remember(text, fallback);
    return ChatMessage(fromAlan: true, text: fallback, cards: cards, mood: _moodFor(cards));
  }

  /// Один запрос к Groq. Если лимит в минуту кончился ненадолго — ждём и повторяем один раз.
  Future<Map<String, dynamic>> _call(List<Map<String, dynamic>> messages, {required double temperature}) async {
    try {
      return await _groq.chat(_request(messages, temperature: temperature));
    } on AiRateLimited catch (e) {
      final wait = e.retryAfter;
      if (wait == null || wait > const Duration(seconds: 8)) rethrow;
      await Future.delayed(wait + const Duration(milliseconds: 300));
      return _groq.chat(_request(messages, temperature: temperature));
    }
  }

  void _remember(String user, String answer) {
    _history
      ..add({'role': 'user', 'content': user})
      ..add({'role': 'assistant', 'content': answer});
    while (_history.length > _historyLimit) {
      _history.removeAt(0);
    }
  }

  static Map<String, dynamic> _parseArgs(dynamic raw) {
    try {
      if (raw is Map) return Map<String, dynamic>.from(raw);
      final s = '${raw ?? ''}'.trim();
      if (s.isEmpty) return {};
      final v = jsonDecode(s);
      return v is Map ? Map<String, dynamic>.from(v) : {};
    } catch (_) {
      return {};
    }
  }

  static String _argsString(dynamic raw) => raw is String ? raw : jsonEncode(raw ?? const {});

  MascotMood _moodFor(List<AlanCard> cards) {
    for (final c in cards) {
      if (c is WeatherCard && c.day.verdict == DayVerdict.bad) return MascotMood.worried;
      if (c is PlanCard && !c.plan.feasible) return MascotMood.worried;
    }
    return cards.isEmpty ? MascotMood.happy : MascotMood.cheering;
  }

  // ───────────── без ИИ: распознаём намерение и вызываем те же инструменты ─────────────

  Future<ChatMessage> _offline(String text, {String? prefix}) async {
    final q = text.toLowerCase();
    final routes = await ref.read(routesProvider.future);
    RouteInfo? named;
    for (final r in routes) {
      final key = r.name.toLowerCase().split(' ').last;
      final stem = key.length > 4 ? key.substring(0, 4) : key;
      if (q.contains(stem)) {
        named = r;
        break;
      }
    }
    final route = named ?? routes.where((r) => r.plannable).firstOrNone;
    final date = _guessDate(q);
    final cards = <AlanCard>[];
    final lines = <String>[if (prefix != null) prefix];

    Future<void> call(String tool, Map<String, dynamic> args) async {
      final out = await _tools.run(tool, args);
      if (out.card != null) cards.add(out.card!);
      if (out.result['error'] != null) lines.add('${out.result['error']}');
    }

    bool has(List<String> words) => words.any(q.contains);

    if (has(['заблуд', 'потерял', 'не знаю где'])) {
      await call('get_safety_info', {'topic': 'lost'});
      lines.add('Остановись и не спускайся в незнакомое ущелье. Вот что делать по шагам.');
    } else if (has(['112', 'помоги', 'травм', 'сломал', 'подвернул'])) {
      await call('get_safety_info', {'topic': has(['травм', 'сломал', 'подвернул']) ? 'injury' : 'emergency'});
      lines.add('Если есть угроза жизни — сразу звони 112.');
    } else if (has(['клещ'])) {
      await call('get_safety_info', {'topic': 'ticks'});
    } else if (has(['гроз', 'молни'])) {
      await call('get_safety_info', {'topic': 'storm'});
    } else if (has(['голова', 'тошн', 'высот'])) {
      await call('get_safety_info', {'topic': 'altitude'});
    } else if (has(['дчс', 'уведом'])) {
      await call('get_safety_info', {'topic': 'notify'});
    } else if (route != null && has(['взять', 'рюкзак', 'вещ', 'собрать', 'одеть', 'надеть'])) {
      await call('get_checklist', {'route_id': route.id, 'date': isoDate(date)});
      lines.add('Собрал список для маршрута ${route.name} на ${_human(date)}.');
    } else if (route != null && has(['погод', 'дожд', 'холод', 'ветер', 'снег'])) {
      await call('get_weather', {'route_id': route.id, 'date': isoDate(date)});
      lines.add('Погода наверху маршрута ${route.name} на ${_human(date)}.');
    } else if (route != null && has(['план', 'спланир', 'пойти на', 'поход на', 'хочу на'])) {
      await call('get_day_plan', {'route_id': route.id, 'date': isoDate(date)});
      await call('get_checklist', {'route_id': route.id, 'date': isoDate(date)});
      lines.add('Вот план на ${_human(date)} и список вещей.');
    } else {
      await call('search_routes', {});
      lines.add(cards.isEmpty
          ? 'Пока не нашёл маршрут под твой уровень.'
          : 'Вот маршруты, которые тебе по силам. Спроси про погоду или план на любой из них.');
    }
    return ChatMessage(fromAlan: true, text: lines.join(' '), cards: cards, mood: _moodFor(cards));
  }

  DateTime _guessDate(String q) {
    final today = almatyToday();
    if (q.contains('послезавтра')) return today.add(const Duration(days: 2));
    if (q.contains('завтра')) return today.add(const Duration(days: 1));
    if (q.contains('сегодня')) return today;
    const days = {'понедельник': 1, 'вторник': 2, 'сред': 3, 'четверг': 4, 'пятниц': 5, 'суббот': 6, 'воскрес': 7};
    for (final e in days.entries) {
      if (q.contains(e.key)) {
        var delta = (e.value - today.weekday) % 7;
        if (delta == 0) delta = 7;
        return today.add(Duration(days: delta));
      }
    }
    // по умолчанию — ближайшая суббота (сегодня, если сегодня суббота)
    return today.add(Duration(days: (6 - today.weekday) % 7));
  }

  String _human(DateTime d) => DateFormat('EEEE, d MMMM', 'ru').format(d);
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(ChatNotifier.new);
