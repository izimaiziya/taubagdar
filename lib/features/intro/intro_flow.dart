import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../alan/alan_mood.dart';
import '../../app/theme.dart';
import '../../data/stores.dart';
import '../../ui/widgets.dart';

class IntroFlow extends ConsumerStatefulWidget {
  const IntroFlow({super.key});
  @override
  ConsumerState<IntroFlow> createState() => _IntroFlowState();
}

class _IntroFlowState extends ConsumerState<IntroFlow> {
  final _pc = PageController();
  final _done = <int>{};
  int _page = 0;
  static const _count = 6;

  void _markDone(int i) => setState(() => _done.add(i));

  void _next() {
    if (_page < _count - 1) {
      _pc.nextPage(duration: 420.ms, curve: Curves.easeOutCubic);
    }
  }

  void _finish({required bool login}) {
    ref.read(profileProvider.notifier).edit((p) => p.copyWith(introSeen: true));
    context.go(login ? '/register?login=1' : '/register');
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _HelloPage(onDone: () => _markDone(0)),
      _BackpackPage(onDone: () => _markDone(1)),
      _OfflinePage(onDone: () => _markDone(2)),
      _TurnaroundPage(onDone: () => _markDone(3)),
      _AlertPage(onDone: () => _markDone(4)),
      _PromisePage(onCreate: () => _finish(login: false), onLogin: () => _finish(login: true)),
    ];

    return Scaffold(
      backgroundColor: Tb.air,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 12, 0),
            child: Row(children: [
              for (var i = 0; i < _count; i++)
                AnimatedContainer(
                  duration: 250.ms,
                  margin: const EdgeInsets.only(right: 6),
                  width: i == _page ? 26 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i <= _page ? Tb.sky : Tb.haze.withValues(alpha: .5),
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
              const Spacer(),
              if (_page < _count - 1)
                TbTextButton('Пропустить', onPressed: () => _pc.animateToPage(_count - 1, duration: 500.ms, curve: Curves.easeOutCubic)),
            ]),
          ),
          Expanded(
            child: PageView(
              controller: _pc,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (i) => setState(() => _page = i),
              children: pages,
            ),
          ),
          if (_page < _count - 1)
            Container(
              color: Tb.sky,
              padding: EdgeInsets.fromLTRB(24, 8, 24, 16 + MediaQuery.of(context).padding.bottom),
              child: AnimatedOpacity(
                duration: 250.ms,
                opacity: _done.contains(_page) ? 1 : 0,
                child: TbButton('Дальше', color: Tb.night, onPressed: _done.contains(_page) ? _next : null),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Общий каркас страницы интро: заголовок, текст, интерактив, хребты внизу.
class _IntroFrame extends StatelessWidget {
  const _IntroFrame({required this.title, required this.text, required this.child, this.seed = 3, this.leading});
  final Widget? leading;
  final String title;
  final String text;
  final Widget child;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (leading != null) ...[leading!, const SizedBox(height: 16)],
          Text(title, style: t.displayMedium),
          const SizedBox(height: 12),
          Text(text, style: t.bodyLarge?.copyWith(color: Tb.ink.withValues(alpha: .85))),
        ]),
      ),
      Expanded(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: child,
          ),
        ),
      ),
      Ridges(seed: seed, height: 110, sky: Tb.air),
    ]);
  }
}

// ─────────────── 1. Знакомство ───────────────

class _HelloPage extends StatefulWidget {
  const _HelloPage({required this.onDone});
  final VoidCallback onDone;
  @override
  State<_HelloPage> createState() => _HelloPageState();
}

class _HelloPageState extends State<_HelloPage> {
  bool _waved = false;
  int _taps = 0;

  @override
  Widget build(BuildContext context) {
    return _IntroFrame(
      leading: const TbLogo(height: 64),
      title: 'Сәлем! Я Алан',
      text: 'Снежный барс из гор над Алматы. Буду твоим напарником от сборов до возвращения домой.',
      seed: 11,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        GestureDetector(
          onTap: () {
            HapticFeedback.mediumImpact();
            setState(() {
              _waved = true;
              _taps++;
            });
            widget.onDone();
          },
          child: AlanFigure(mood: _waved ? MascotMood.cheering : MascotMood.happy, height: 250, breathe: !_waved)
              .animate(key: ValueKey(_taps), autoPlay: _taps > 0)
              .scaleXY(begin: 1, end: 1.08, duration: 160.ms, curve: Curves.easeOut)
              .then()
              .scaleXY(begin: 1.08, end: 1, duration: 220.ms, curve: Curves.elasticOut),
        ),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: 250.ms,
          child: Text(
            _waved ? 'Рад знакомству!' : 'Нажми на меня',
            key: ValueKey(_waved),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Tb.skyDeep),
          ),
        ),
      ]),
    );
  }
}

// ─────────────── 2. Рюкзак ───────────────

class _BackpackPage extends StatefulWidget {
  const _BackpackPage({required this.onDone});
  final VoidCallback onDone;
  @override
  State<_BackpackPage> createState() => _BackpackPageState();
}

class _BackpackPageState extends State<_BackpackPage> {
  static const _items = [
    ('Фонарик', Icons.flashlight_on_rounded),
    ('Вода', Icons.water_drop_rounded),
    ('Куртка', Icons.checkroom_rounded),
  ];
  final _packed = <String>{};

  @override
  Widget build(BuildContext context) {
    final all = _packed.length == _items.length;
    return _IntroFrame(
      title: 'Соберём рюкзак',
      text: 'Перед каждым походом я подскажу, что взять, — по погоде и маршруту. Перетащи вещи в рюкзак.',
      seed: 23,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: [
          for (final (name, icon) in _items)
            if (!_packed.contains(name))
              Draggable<String>(
                data: name,
                feedback: Material(color: Colors.transparent, child: _ItemChip(name, icon, lifted: true)),
                childWhenDragging: Opacity(opacity: .3, child: _ItemChip(name, icon)),
                child: _ItemChip(name, icon),
              )
            else
              Opacity(opacity: .0, child: _ItemChip(name, icon)),
        ]),
        const SizedBox(height: 28),
        DragTarget<String>(
          onAcceptWithDetails: (d) {
            HapticFeedback.lightImpact();
            setState(() => _packed.add(d.data));
            if (_packed.length == _items.length) widget.onDone();
          },
          builder: (context, candidate, _) => AnimatedContainer(
            duration: 200.ms,
            width: 170,
            height: 170,
            decoration: BoxDecoration(
              color: candidate.isNotEmpty ? Tb.sky : Tb.snow,
              shape: BoxShape.circle,
              border: Border.all(color: Tb.sky, width: 3),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.backpack_rounded, size: 64, color: candidate.isNotEmpty ? Colors.white : Tb.sky),
              const SizedBox(height: 6),
              Text('${_packed.length} из ${_items.length}',
                  style: TextStyle(
                      fontFamily: Tb.display,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: candidate.isNotEmpty ? Colors.white : Tb.night)),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 70,
          child: all ? const AlanSays('Отлично! Такой список я соберу для каждого похода.', mood: MascotMood.cheering, avatar: 56) : null,
        ),
      ]),
    );
  }
}

class _ItemChip extends StatelessWidget {
  const _ItemChip(this.name, this.icon, {this.lifted = false});
  final String name;
  final IconData icon;
  final bool lifted;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: Tb.snow,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: lifted ? Tb.sky : Tb.mist, width: 2),
          boxShadow: lifted ? [BoxShadow(color: Tb.sky.withValues(alpha: .25), blurRadius: 18, offset: const Offset(0, 8))] : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Tb.sky),
          const SizedBox(width: 8),
          Text(name, style: const TextStyle(fontFamily: Tb.body, fontWeight: FontWeight.w600, fontSize: 16, color: Tb.night)),
        ]),
      );
}

// ─────────────── 3. Без связи ───────────────

class _OfflinePage extends StatefulWidget {
  const _OfflinePage({required this.onDone});
  final VoidCallback onDone;
  @override
  State<_OfflinePage> createState() => _OfflinePageState();
}

class _OfflinePageState extends State<_OfflinePage> {
  bool _airplane = false;

  @override
  Widget build(BuildContext context) {
    return _IntroFrame(
      title: 'Без связи я всё равно рядом',
      text: 'В горах часто нет сети. Карта, время разворота и помощь работают без интернета. Выключи связь и проверь.',
      seed: 5,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Sheet(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(children: [
            Icon(_airplane ? Icons.airplanemode_active_rounded : Icons.signal_cellular_alt_rounded,
                color: _airplane ? Tb.sky : Tb.slate, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Text('Авиарежим', style: Theme.of(context).textTheme.titleLarge),
            ),
            Switch.adaptive(
              value: _airplane,
              activeTrackColor: Tb.sky,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                setState(() => _airplane = v);
                if (v) widget.onDone();
              },
            ),
          ]),
        ),
        const SizedBox(height: 28),
        AlanSays(
          _airplane ? 'Связи нет, а я на месте. Тропа — в 40 метрах справа, разворот в 14:30.' : 'Пока связь есть. Выключи её.',
          mood: _airplane ? MascotMood.calm : MascotMood.thinking,
          avatar: 88,
        ),
      ]),
    );
  }
}

// ─────────────── 4. Время разворота ───────────────

class _TurnaroundPage extends StatefulWidget {
  const _TurnaroundPage({required this.onDone});
  final VoidCallback onDone;
  @override
  State<_TurnaroundPage> createState() => _TurnaroundPageState();
}

class _TurnaroundPageState extends State<_TurnaroundPage> {
  double _hour = 10;

  @override
  Widget build(BuildContext context) {
    final h = _hour.floor();
    final m = ((_hour - h) * 60).round();
    final time = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    final (text, mood) = _hour < 13.5
        ? ('$time — времени много, идём наверх.', MascotMood.happy)
        : _hour < 15
            ? ('$time — скоро разворот. В 15:00 поворачиваем вниз.', MascotMood.thinking)
            : ('$time — пора вниз, иначе спускаться придётся в темноте.', MascotMood.worried);
    final evening = ((_hour - 9) / 10).clamp(0.0, 1.0);

    return _IntroFrame(
      title: 'Я знаю, когда пора поворачивать',
      text: 'Чаще всего беда случается, когда не успевают вернуться до темноты или непогоды. Передвинь солнце.',
      seed: 41,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          height: 150,
          decoration: BoxDecoration(
            color: Color.lerp(Tb.snow, const Color(0xFF3B5A86), evening * .85),
            borderRadius: BorderRadius.circular(26),
          ),
          child: Stack(children: [
            Positioned(
              left: 24 + evening * 220,
              top: 16 + (evening - .5).abs() * 90,
              child: Icon(Icons.circle, size: 40, color: Color.lerp(const Color(0xFFFFD166), const Color(0xFFFF9F68), evening)),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26)),
                child: Ridges(seed: 8, height: 70, sky: Colors.transparent, front: Tb.night.withValues(alpha: .9), snowCaps: false),
              ),
            ),
          ]),
        ),
        Slider(
          value: _hour,
          min: 9,
          max: 19,
          divisions: 40,
          activeColor: Tb.sky,
          onChanged: (v) {
            setState(() => _hour = v);
            if (v >= 15) widget.onDone();
          },
        ),
        const SizedBox(height: 8),
        AlanSays(text, mood: mood, avatar: 72),
      ]),
    );
  }
}

// ─────────────── 5. Тревога близким ───────────────

class _AlertPage extends StatefulWidget {
  const _AlertPage({required this.onDone});
  final VoidCallback onDone;
  @override
  State<_AlertPage> createState() => _AlertPageState();
}

class _AlertPageState extends State<_AlertPage> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 2))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        HapticFeedback.heavyImpact();
        setState(() => _sent = true);
        widget.onDone();
      }
    });
  bool _sent = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _IntroFrame(
      title: 'Не вернёшься вовремя — я позову помощь',
      text: 'Даже если твой телефон разрядится. Удерживай кнопку, чтобы увидеть, что получат близкие.',
      seed: 17,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (!_sent)
          Listener(
            onPointerDown: (_) => _c.forward(),
            onPointerUp: (_) {
              if (!_sent) _c.reverse();
            },
            onPointerCancel: (_) {
              if (!_sent) _c.reverse();
            },
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, __) => SizedBox(
                width: 150,
                height: 150,
                child: Stack(alignment: Alignment.center, children: [
                  SizedBox(
                    width: 150,
                    height: 150,
                    child: CircularProgressIndicator(
                      value: _c.value,
                      strokeWidth: 8,
                      color: Tb.sky,
                      backgroundColor: Tb.snow,
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  Container(
                    width: 118,
                    height: 118,
                    decoration: const BoxDecoration(color: Tb.night, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: const Text('Удерживай',
                        style: TextStyle(fontFamily: Tb.body, fontWeight: FontWeight.w600, color: Colors.white, fontSize: 16)),
                  ),
                ]),
              ),
            ),
          )
        else ...[
          Sheet(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.send_rounded, color: Tb.sky, size: 20),
                const SizedBox(width: 8),
                Text('Сообщение маме', style: Theme.of(context).textTheme.labelMedium),
              ]),
              const SizedBox(height: 10),
              Text('Айгерим не вернулась из похода на Кок-Жайляу вовремя.',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text('Последняя точка: 43.14239, 77.00433 в 13:42. Попробуйте дозвониться. Если не отвечает — позвоните 112.',
                  style: Theme.of(context).textTheme.bodyMedium),
            ]),
          ).animate().fadeIn(duration: 300.ms).slideY(begin: .15, curve: Curves.easeOutCubic),
          const SizedBox(height: 18),
          const AlanSays('Такое сообщение уйдёт, только если ты не отметишься дома.', mood: MascotMood.calm, avatar: 64),
        ],
      ]),
    );
  }
}

// ─────────────── 6. Обещание и старт ───────────────

class _PromisePage extends StatefulWidget {
  const _PromisePage({required this.onCreate, required this.onLogin});
  final VoidCallback onCreate;
  final VoidCallback onLogin;
  @override
  State<_PromisePage> createState() => _PromisePageState();
}

class _PromisePageState extends State<_PromisePage> {
  bool _agree = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 20, 24, 0), children: [
          Text('Прежде чем начнём', style: t.displayMedium),
          const SizedBox(height: 18),
          const AlanSays('Я помощник, а не спасатель. Я не заменяю подготовку, снаряжение и здравый смысл.',
              mood: MascotMood.calm, avatar: 76),
          const SizedBox(height: 20),
          for (final line in const [
            'Мои советы основаны на открытых данных и прогнозе погоды. Они могут ошибаться.',
            'Если есть угроза жизни — звони 112, не жди меня.',
            'Перед походом в горы туристы обязаны уведомить ДЧС. Я помогу это сделать.',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(padding: EdgeInsets.only(top: 3), child: Icon(Icons.check_circle_rounded, color: Tb.sky, size: 20)),
                const SizedBox(width: 10),
                Expanded(child: Text(line, style: t.bodyMedium)),
              ]),
            ),
          const SizedBox(height: 4),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _agree = !_agree),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                Checkbox(value: _agree, activeColor: Tb.sky, onChanged: (v) => setState(() => _agree = v ?? false)),
                Expanded(child: Text('Понятно, я отвечаю за своё решение идти в горы', style: t.titleMedium)),
              ]),
            ),
          ),
        ]),
      ),
      Container(
        color: Tb.sky,
        padding: EdgeInsets.fromLTRB(24, 14, 24, 12 + MediaQuery.of(context).padding.bottom),
        child: Column(children: [
          TbButton('Создать аккаунт', color: Tb.night, onPressed: _agree ? widget.onCreate : null),
          const SizedBox(height: 4),
          TextButton(
            onPressed: _agree ? widget.onLogin : null,
            style: TextButton.styleFrom(foregroundColor: Colors.white, minimumSize: const Size(0, 48)),
            child: const Text('У меня уже есть аккаунт',
                style: TextStyle(fontFamily: Tb.body, fontWeight: FontWeight.w600, fontSize: 16)),
          ),
        ]),
      ),
    ]);
  }
}
