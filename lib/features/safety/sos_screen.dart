import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/env.dart';
import '../../app/theme.dart';
import '../../core/send.dart';
import '../../data/stores.dart';

class SosScreen extends ConsumerStatefulWidget {
  const SosScreen({super.key});
  @override
  ConsumerState<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends ConsumerState<SosScreen> {
  Position? _pos;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  Future<void> _locate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw 'Геолокация выключена. Включи её в шторке телефона.';
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw 'Нет доступа к геолокации. Разреши его в настройках.';
      }
      // Сначала мгновенно — последняя известная точка, потом точная.
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted) setState(() => _pos = last);
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, timeLimit: Duration(seconds: 30)),
      );
      if (mounted) setState(() => _pos = p);
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _message() {
    final p = ref.read(profileProvider);
    final pos = _pos;
    final lines = <String>[
      '${p.name.isEmpty ? 'Мне' : '${p.name}: мне'} нужна помощь в горах.',
      if (pos != null) ...[
        'Координаты: ${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)} (±${pos.accuracy.round()} м)',
        if (pos.altitude != 0) 'Высота: ~${pos.altitude.round()} м',
        'Карта: https://www.openstreetmap.org/?mlat=${pos.latitude.toStringAsFixed(5)}&mlon=${pos.longitude.toStringAsFixed(5)}#map=16/${pos.latitude.toStringAsFixed(5)}/${pos.longitude.toStringAsFixed(5)}',
      ],
      'Время: ${hhmm(almatyNow())}',
      if (p.healthVisibleToRescuers && p.health.isNotEmpty) 'Здоровье: ${p.health.map(_healthRu).join(', ')}',
      'Если не могу ответить — звоните 112.',
    ];
    return lines.join('\n');
  }

  static String _healthRu(String k) =>
      const {'knees': 'колени', 'asthma': 'астма', 'heart': 'сердце', 'diabetes': 'диабет', 'allergy': 'аллергия'}[k] ?? k;

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(profileProvider);
    final pos = _pos;
    const white = TextStyle(fontFamily: Tb.body, color: Colors.white, fontSize: 16);

    return Scaffold(
      backgroundColor: Tb.night,
      appBar: AppBar(foregroundColor: Colors.white, title: const Text('SOS', style: TextStyle(color: Colors.white))),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [
        // Звонок — первым и самым большим.
        SizedBox(
          height: 76,
          child: FilledButton.icon(
            onPressed: () {
              HapticFeedback.heavyImpact();
              launchUrl(Uri.parse('tel:112'));
            },
            style: FilledButton.styleFrom(
              backgroundColor: Tb.danger,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            ),
            icon: const Icon(Icons.call_rounded, size: 30),
            label: const Text('Позвонить 112',
                style: TextStyle(fontFamily: Tb.display, fontWeight: FontWeight.w800, fontSize: 22)),
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: .08), borderRadius: BorderRadius.circular(24)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Твои координаты', style: white.copyWith(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 8),
            if (pos == null && _loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(color: Tb.haze, backgroundColor: Colors.white12),
              )
            else if (pos == null)
              Text(_error ?? 'Не удалось определить место.', style: white)
            else ...[
              SelectableText('${pos.latitude.toStringAsFixed(5)}\n${pos.longitude.toStringAsFixed(5)}',
                  style: const TextStyle(
                      fontFamily: Tb.display, fontWeight: FontWeight.w800, fontSize: 34, color: Colors.white, height: 1.15)),
              const SizedBox(height: 10),
              Text(
                [
                  'точность ±${pos.accuracy.round()} м',
                  if (pos.altitude != 0) 'высота ~${pos.altitude.round()} м',
                  if (_loading) 'уточняю…',
                ].join(', '),
                style: white.copyWith(color: Colors.white70, fontSize: 14),
              ),
            ],
            const SizedBox(height: 12),
            Row(children: [
              TextButton.icon(
                onPressed: _loading ? null : _locate,
                style: TextButton.styleFrom(foregroundColor: Tb.haze),
                icon: const Icon(Icons.my_location_rounded),
                label: const Text('Обновить'),
              ),
              if (pos != null)
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}'));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Координаты скопированы')));
                  },
                  style: TextButton.styleFrom(foregroundColor: Tb.haze),
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Копировать'),
                ),
            ]),
          ]),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 60,
          child: FilledButton.icon(
            onPressed: () async {
              final phones = ref.read(profileProvider).contacts.map((c) => c.phone).toList();
              final ok = await sendSms(phones, _message());
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(ok
                    ? 'Текст скопирован. Если SMS не уйдёт — вставь его в любой мессенджер.'
                    : 'Не открылось SMS. Текст скопирован — вставь его в мессенджер.'),
              ));
            },
            style: FilledButton.styleFrom(
              backgroundColor: Tb.sky,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            icon: const Icon(Icons.send_rounded),
            label: const Text('Отправить координаты по SMS', style: TextStyle(fontFamily: Tb.body, fontWeight: FontWeight.w600, fontSize: 17)),
          ),
        ),
        if (p.contacts.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text('Позвонить', style: white.copyWith(color: Colors.white70, fontSize: 14)),
          for (final c in p.contacts)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(c.name, style: white.copyWith(fontWeight: FontWeight.w600)),
              subtitle: Text(c.phone, style: white.copyWith(color: Colors.white60, fontSize: 14)),
              trailing: IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: .12)),
                onPressed: () => launchUrl(Uri.parse('tel:${c.phone}')),
                icon: const Icon(Icons.call_rounded, color: Colors.white),
              ),
            ),
        ],
        const SizedBox(height: 22),
        Text(
          'Если связи нет: поднимись чуть выше на открытое место и попробуй снова. Береги заряд, оставайся на месте, если не знаешь дороги.',
          style: white.copyWith(color: Colors.white70, fontSize: 14.5, height: 1.45),
        ),
      ]),
    );
  }
}
