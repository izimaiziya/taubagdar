import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../alan/alan_mood.dart';
import '../../app/env.dart';
import '../../app/theme.dart';
import '../../core/send.dart';
import '../../data/models.dart';
import '../../data/stores.dart';
import '../../ui/widgets.dart';

enum _Step { name, email, otp, phone, age, experience, altitude, fitness, company, gear, health, contact, permissions, summary }

class RegisterFlow extends ConsumerStatefulWidget {
  const RegisterFlow({super.key, this.loginOnly = false});
  final bool loginOnly;
  @override
  ConsumerState<RegisterFlow> createState() => _RegisterFlowState();
}

class _RegisterFlowState extends ConsumerState<RegisterFlow> {
  late final List<_Step> _steps = [
    if (widget.loginOnly && Env.hasSupabase)
      ...[_Step.email, _Step.otp, _Step.name]
    else
      ...[_Step.name, if (Env.hasSupabase) ...[_Step.email, _Step.otp]],
    _Step.phone,
    _Step.age,
    _Step.experience,
    _Step.altitude,
    _Step.fitness,
    _Step.company,
    _Step.gear,
    _Step.health,
    _Step.contact,
    _Step.permissions,
    _Step.summary,
  ];
  int _i = 0;
  bool _busy = false;

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _otp = TextEditingController();
  final _phone = TextEditingController();
  final _cName = TextEditingController();
  final _cRelation = TextEditingController();
  final _cPhone = TextEditingController();
  LocationPermission? _locPerm;

  _Step get _step => _steps[_i];
  UserProfile get _p => ref.read(profileProvider);
  void _set(UserProfile Function(UserProfile) f) => ref.read(profileProvider.notifier).edit(f);

  @override
  void initState() {
    super.initState();
    final p = ref.read(profileProvider);
    _name.text = p.name;
    _email.text = p.email;
    _phone.text = p.phone.replaceFirst('+7', '');
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _otp, _phone, _cName, _cRelation, _cPhone]) {
      c.dispose();
    }
    super.dispose();
  }

  // ───────────── навигация по шагам ─────────────

  bool get _valid {
    final p = ref.watch(profileProvider);
    return switch (_step) {
      _Step.name => _name.text.trim().length >= 2,
      _Step.email => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim()),
      _Step.otp => _otp.text.trim().length == 6,
      _Step.phone => _phone.text.replaceAll(RegExp(r'\D'), '').length == 10,
      _Step.age => p.ageGroup.isNotEmpty,
      _Step.experience => p.experience != null,
      _Step.altitude => true,
      _Step.fitness => true,
      _Step.company => p.company != null,
      _Step.contact => _cName.text.trim().isNotEmpty && _cPhone.text.replaceAll(RegExp(r'\D'), '').length >= 10,
      _ => true,
    };
  }

  bool get _optional => const {_Step.gear, _Step.health, _Step.contact, _Step.permissions}.contains(_step);

  Future<void> _next({bool skip = false}) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      if (!skip) {
        final ok = await _commit();
        if (!ok) return;
      }
      if (_i < _steps.length - 1) {
        setState(() => _i++);
      } else {
        _set((p) => p.copyWith(registered: true));
        await ref.read(profileProvider.notifier).pushToCloud();
        if (mounted) context.go('/app');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _back() {
    if (_i > 0) {
      setState(() => _i--);
    } else {
      context.go('/intro');
    }
  }

  /// Сохраняет ответ текущего шага. false — остаться на шаге.
  Future<bool> _commit() async {
    switch (_step) {
      case _Step.name:
        _set((p) => p.copyWith(name: _name.text.trim()));
      case _Step.email:
        try {
          await Supabase.instance.client.auth.signInWithOtp(email: _email.text.trim(), shouldCreateUser: true);
          _set((p) => p.copyWith(email: _email.text.trim()));
        } on AuthException catch (e) {
          _toast('Не получилось отправить код: ${e.message}');
          return false;
        } catch (_) {
          _toast('Нет связи. Проверь интернет и попробуй ещё раз.');
          return false;
        }
      case _Step.otp:
        try {
          await Supabase.instance.client.auth
              .verifyOTP(email: _email.text.trim(), token: _otp.text.trim(), type: OtpType.email);
        } on AuthException {
          _toast('Код не подошёл. Проверь цифры или запроси новый.');
          return false;
        } catch (_) {
          _toast('Нет связи. Попробуй ещё раз.');
          return false;
        }
        if (widget.loginOnly) {
          final restored = await ref.read(profileProvider.notifier).pullFromCloud();
          if (restored && mounted) {
            context.go('/app');
            return false;
          }
        }
      case _Step.phone:
        _set((p) => p.copyWith(phone: '+7${_phone.text.replaceAll(RegExp(r'\D'), '')}'));
      case _Step.contact:
        _saveContact();
      default:
        break;
    }
    return true;
  }

  void _saveContact() {
    final c = EmergencyContact(
      name: _cName.text.trim(),
      relation: _cRelation.text.trim(),
      phone: '+7${_cPhone.text.replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^[78](?=\d{10}$)'), '')}',
      inviteToken: EmergencyContact.newToken(),
    );
    _set((p) => p.copyWith(contacts: [...p.contacts.where((x) => x.phone != c.phone), c]));
  }

  void _toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  // ───────────── вопрос Алана для шага ─────────────

  (String, String?, MascotMood) _question(UserProfile p) {
    final n = p.name.isEmpty ? '' : ', ${p.name}';
    return switch (_step) {
      _Step.name => ('Как тебя зовут?', null, MascotMood.happy),
      _Step.email => ('Куда прислать код для входа$n?', 'Пароль не нужен — каждый раз пришлю код на почту.', MascotMood.thinking),
      _Step.otp => ('Введи код из письма', 'Письмо ушло на ${_email.text.trim()}.', MascotMood.thinking),
      _Step.phone => ('Твой номер телефона?', 'Он попадёт только в сообщение близким, если понадобится помощь.', MascotMood.calm),
      _Step.age => ('Сколько тебе лет$n?', null, MascotMood.happy),
      _Step.experience => ('Был ли у тебя опыт в горах?', 'От этого зависит, какие маршруты я буду предлагать.', MascotMood.thinking),
      _Step.altitude => ('На какой высоте ты уже бывал?', 'Выше 2500–3000 м бывает горная болезнь. Я буду следить.', MascotMood.thinking),
      _Step.fitness => ('Как у тебя с выносливостью?', 'Так я точнее посчитаю время на маршруте.', MascotMood.happy),
      _Step.company => ('С кем ты обычно ходишь?', null, MascotMood.happy),
      _Step.gear => ('Что из снаряжения у тебя уже есть?', 'Остальное я отмечу в списках как «купить или взять напрокат».', MascotMood.cheering),
      _Step.health => ('Есть что-то о здоровье, что важно знать спасателям?',
          'Это видишь только ты. ИИ эти данные не получает.', MascotMood.calm),
      _Step.contact => ('Кому мне написать, если ты не вернёшься?', 'Лучше тому, кто всегда на связи и не в походе вместе с тобой.', MascotMood.worried),
      _Step.permissions => ('Разрешишь мне видеть, где ты?', 'Геолокация нужна, чтобы вести по тропе и показать координаты спасателям.', MascotMood.calm),
      _Step.summary => ('Вот что я о тебе понял', null, MascotMood.cheering),
    };
  }

  // ───────────── интерфейс ─────────────

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(profileProvider);
    final (q, sub, mood) = _question(p);
    final t = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 24, 0),
            child: Row(children: [
              IconButton(onPressed: _back, icon: const Icon(Icons.arrow_back_rounded), color: Tb.night),
              const SizedBox(width: 4),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: (_i + 1) / _steps.length),
                    duration: 350.ms,
                    builder: (_, v, __) =>
                        LinearProgressIndicator(value: v, minHeight: 8, color: Tb.sky, backgroundColor: Tb.mist),
                  ),
                ),
              ),
            ]),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: 280.ms,
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(position: Tween(begin: const Offset(.06, 0), end: Offset.zero).animate(a), child: c),
              ),
              child: ListView(
                key: ValueKey(_step),
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                children: [
                  Align(alignment: Alignment.centerLeft, child: AlanFigure(mood: mood, height: 130)),
                  const SizedBox(height: 14),
                  Text(q, style: t.displaySmall),
                  if (sub != null) ...[
                    const SizedBox(height: 8),
                    Text(sub, style: t.bodyLarge?.copyWith(color: Tb.slate)),
                  ],
                  const SizedBox(height: 24),
                  _body(p),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Column(children: [
              TbButton(
                _step == _Step.summary ? 'Войти в TauBağdar' : (_step == _Step.email ? 'Получить код' : 'Дальше'),
                onPressed: _valid && !_busy ? () => _next() : null,
              ),
              if (_optional) TbTextButton('Пропустить', onPressed: _busy ? null : () => _next(skip: true)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _body(UserProfile p) {
    switch (_step) {
      case _Step.name:
        return _Field(controller: _name, hint: 'Имя', caps: true, onChanged: () => setState(() {}));
      case _Step.email:
        return _Field(controller: _email, hint: 'you@mail.kz', keyboard: TextInputType.emailAddress, onChanged: () => setState(() {}));
      case _Step.otp:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: _otp,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontFamily: Tb.display, fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: 14),
            decoration: const InputDecoration(counterText: '', hintText: '••••••'),
            onChanged: (v) {
              setState(() {});
              if (v.length == 6) _next();
            },
          ),
          const SizedBox(height: 8),
          TbTextButton('Отправить код ещё раз', onPressed: () async {
            try {
              await Supabase.instance.client.auth.signInWithOtp(email: _email.text.trim());
              _toast('Отправил новый код.');
            } catch (_) {
              _toast('Не получилось. Подожди минуту и попробуй снова.');
            }
          }),
        ]);
      case _Step.phone:
        return _Field(
          controller: _phone,
          hint: '700 000 00 00',
          prefix: '+7 ',
          keyboard: TextInputType.phone,
          digits: 10,
          onChanged: () => setState(() {}),
        );
      case _Step.age:
        return _Options(
          options: const [('under18', 'До 18', null), ('18-35', '18–35', null), ('36-55', '36–55', null), ('55+', 'Старше 55', null)],
          selected: {p.ageGroup},
          onTap: (v) => _set((x) => x.copyWith(ageGroup: v)),
          footer: p.ageGroup == 'under18'
              ? const AlanSays('Тогда я буду предлагать походы только со взрослыми.', mood: MascotMood.calm, avatar: 48)
              : null,
        );
      case _Step.experience:
        return _Options(
          options: const [
            ('never', 'Ни разу', 'Это будет мой первый поход'),
            ('easyTrails', 'Пару раз', 'Ходил по простым тропам'),
            ('regular', 'Хожу регулярно', 'Несколько походов за сезон'),
            ('alpine', 'Есть альпинистский опыт', 'Восхождения, снаряжение, курсы'),
          ],
          selected: {p.experience?.name ?? ''},
          onTap: (v) => _set((x) => x.copyWith(experience: Experience.values.byName(v))),
        );
      case _Step.altitude:
        return _Options(
          options: const [('0', 'Ниже 2000 м', null), ('1', '2000–3000 м', null), ('2', 'Выше 3000 м', null), ('-1', 'Не знаю', null)],
          selected: {'${p.maxAltitude}'},
          onTap: (v) => _set((x) => x.copyWith(maxAltitude: int.parse(v))),
        );
      case _Step.fitness:
        return _Options(
          options: const [
            ('0', 'Запыхаюсь на пятом этаже', null),
            ('1', 'Могу час идти в горку', null),
            ('2', 'Регулярно тренируюсь', null),
          ],
          selected: {'${p.fitness}'},
          onTap: (v) => _set((x) => x.copyWith(fitness: int.parse(v))),
        );
      case _Step.company:
        return _Options(
          options: const [('solo', 'Один', null), ('friends', 'С друзьями', null), ('family', 'С семьёй и детьми', null), ('guide', 'С гидом', null)],
          selected: {p.company?.name ?? ''},
          onTap: (v) => _set((x) => x.copyWith(company: Company.values.byName(v))),
          footer: p.company == Company.solo && p.expLevel == 0
              ? const AlanSays('Первый поход лучше пройти хотя бы вдвоём. Я буду об этом напоминать.', mood: MascotMood.worried, avatar: 48)
              : null,
        );
      case _Step.gear:
        return _Chips(
          options: const {
            'boots': 'Треккинговые ботинки',
            'poles': 'Палки',
            'shell': 'Мембранная куртка',
            'headlamp': 'Налобный фонарь',
            'powerbank': 'Пауэрбанк',
            'firstaid': 'Аптечка',
            'thermos': 'Термос',
          },
          selected: p.gear,
          onChanged: (s) => _set((x) => x.copyWith(gear: s)),
        );
      case _Step.health:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Chips(
            options: const {'knees': 'Колени', 'asthma': 'Астма', 'heart': 'Сердце', 'diabetes': 'Диабет', 'allergy': 'Аллергия'},
            selected: p.health,
            onChanged: (s) => _set((x) => x.copyWith(health: s)),
          ),
          const SizedBox(height: 16),
          Sheet(
            padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: p.healthVisibleToRescuers,
              activeTrackColor: Tb.sky,
              title: Text('Показывать спасателям', style: Theme.of(context).textTheme.titleMedium),
              subtitle: const Text('Только на странице тревоги, если ты не вернёшься'),
              onChanged: (v) => _set((x) => x.copyWith(healthVisibleToRescuers: v)),
            ),
          ),
        ]);
      case _Step.contact:
        return Column(children: [
          _Field(controller: _cName, hint: 'Имя', caps: true, onChanged: () => setState(() {})),
          const SizedBox(height: 12),
          _Field(controller: _cRelation, hint: 'Кем приходится (мама, друг…)', autofocus: false, onChanged: () => setState(() {})),
          const SizedBox(height: 12),
          _Field(controller: _cPhone, hint: '700 000 00 00', prefix: '+7 ', keyboard: TextInputType.phone, digits: 10, autofocus: false, onChanged: () => setState(() {})),
          const SizedBox(height: 18),
          if (Env.telegramBot.isNotEmpty)
            OutlinedButton.icon(
              onPressed: _valid
                  ? () {
                      _saveContact();
                      final c = ref.read(profileProvider).contacts.last;
                      shareToTelegram(
                        'https://t.me/${Env.telegramBot}?start=${c.inviteToken}',
                        '${_p.name} добавил(а) тебя экстренным контактом в TauBağdar. Открой ссылку и нажми Start — тогда я смогу написать тебе, если что-то случится в горах.',
                      );
                    }
                  : null,
              icon: const Icon(Icons.send_rounded),
              label: const Text('Отправить приглашение'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
            )
          else
            Text('Приглашение в Telegram станет доступно после подключения сервера.', style: Theme.of(context).textTheme.bodySmall),
        ]);
      case _Step.permissions:
        final granted = _locPerm == LocationPermission.always || _locPerm == LocationPermission.whileInUse;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Sheet(
            child: Row(children: [
              Icon(granted ? Icons.check_circle_rounded : Icons.location_on_rounded, color: granted ? Tb.safe : Tb.sky, size: 30),
              const SizedBox(width: 14),
              Expanded(
                child: Text(granted ? 'Геолокация разрешена' : 'Геолокация', style: Theme.of(context).textTheme.titleLarge),
              ),
              if (!granted)
                FilledButton(
                  onPressed: () async {
                    var perm = await Geolocator.checkPermission();
                    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
                    setState(() => _locPerm = perm);
                    if (perm == LocationPermission.deniedForever) {
                      _toast('Разрешение можно включить в настройках телефона.');
                    }
                  },
                  style: FilledButton.styleFrom(backgroundColor: Tb.sky),
                  child: const Text('Разрешить'),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          Text('Уведомления и фоновую геолокацию я попрошу, когда ты впервые спланируешь поход.',
              style: Theme.of(context).textTheme.bodySmall),
        ]);
      case _Step.summary:
        return Sheet(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name, style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 10),
            Pill(p.levelTitle, filled: true),
            const SizedBox(height: 14),
            Text(p.levelHint, style: Theme.of(context).textTheme.bodyLarge),
            const Divider(height: 32, color: Tb.mist),
            _SummaryRow(Icons.favorite_rounded, p.contacts.isEmpty ? 'Экстренный контакт не добавлен' : 'Экстренный контакт: ${p.contacts.first.name}'),
            _SummaryRow(Icons.backpack_rounded, p.gear.isEmpty ? 'Снаряжение пока не отмечено' : 'Снаряжение: ${p.gear.length} из 7'),
            _SummaryRow(Icons.speed_rounded, 'Твой темп: ×${p.paceFactor.toStringAsFixed(2)} к среднему, уточню после первого похода'),
          ]),
        ).animate().fadeIn(duration: 300.ms).scaleXY(begin: .97, curve: Curves.easeOutBack);
    }
  }
}

// ─────────────── элементы формы ───────────────

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    this.keyboard,
    this.prefix,
    this.caps = false,
    this.digits,
    this.autofocus = true,
    required this.onChanged,
  });
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboard;
  final String? prefix;
  final bool caps;
  final int? digits;
  final bool autofocus;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        autofocus: autofocus,
        keyboardType: keyboard,
        textCapitalization: caps ? TextCapitalization.words : TextCapitalization.none,
        inputFormatters: digits != null
            ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(digits)]
            : null,
        style: const TextStyle(fontFamily: Tb.body, fontSize: 19, fontWeight: FontWeight.w500, color: Tb.night),
        decoration: InputDecoration(
          hintText: hint,
          prefixText: prefix,
          prefixStyle: const TextStyle(fontFamily: Tb.body, fontSize: 19, fontWeight: FontWeight.w500, color: Tb.slate),
        ),
        onChanged: (_) => onChanged(),
      );
}

class _Options extends StatelessWidget {
  const _Options({required this.options, required this.selected, required this.onTap, this.footer});
  final List<(String, String, String?)> options;
  final Set<String> selected;
  final ValueChanged<String> onTap;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => Column(children: [
        for (final (value, title, sub) in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: selected.contains(value) ? Tb.sky : Tb.snow,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTap(value);
                },
                child: Container(
                  constraints: const BoxConstraints(minHeight: 64),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(title,
                            style: TextStyle(
                                fontFamily: Tb.body,
                                fontWeight: FontWeight.w600,
                                fontSize: 17,
                                color: selected.contains(value) ? Colors.white : Tb.night)),
                        if (sub != null)
                          Text(sub,
                              style: TextStyle(
                                  fontFamily: Tb.body, fontSize: 14, color: selected.contains(value) ? Colors.white70 : Tb.slate)),
                      ]),
                    ),
                    if (selected.contains(value)) const Icon(Icons.check_rounded, color: Colors.white),
                  ]),
                ),
              ),
            ),
          ),
        if (footer != null) Padding(padding: const EdgeInsets.only(top: 8), child: footer!),
      ]);
}

class _Chips extends StatelessWidget {
  const _Chips({required this.options, required this.selected, required this.onChanged});
  final Map<String, String> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 10, runSpacing: 10, children: [
        for (final e in options.entries)
          FilterChip(
            label: Text(e.value),
            selected: selected.contains(e.key),
            onSelected: (on) => onChanged(on ? {...selected, e.key} : ({...selected}..remove(e.key))),
            showCheckmark: false,
            labelStyle: TextStyle(
                fontFamily: Tb.body,
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
                color: selected.contains(e.key) ? Colors.white : Tb.night),
            backgroundColor: Tb.snow,
            selectedColor: Tb.sky,
            side: BorderSide(color: selected.contains(e.key) ? Tb.sky : Tb.mist, width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
      ]);
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: Tb.sky),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ]),
      );
}
