import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/env.dart';
import 'app/theme.dart';
import 'data/models.dart';
import 'data/stores.dart';
import 'features/alan/chat_screen.dart';
import 'features/hike/hike_screen.dart';
import 'features/intro/intro_flow.dart';
import 'features/register/register_flow.dart';
import 'features/routes/route_detail_screen.dart';
import 'features/safety/sos_screen.dart';
import 'features/shell/main_shell.dart';
import 'features/trips/trip_detail_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru');
  LicenseRegistry.addLicense(() async* {
    for (final f in const ['MontserratAlternates', 'Onest']) {
      yield LicenseEntryWithLineBreaks([f], await rootBundle.loadString('assets/licenses/OFL-$f.txt'));
    }
  });
  if (Env.hasSupabase) {
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseKey);
  }
  final prefs = await SharedPreferences.getInstance();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(ProviderScope(overrides: [prefsProvider.overrideWithValue(prefs)], child: const TauBagdarApp()));
}

class TauBagdarApp extends ConsumerStatefulWidget {
  const TauBagdarApp({super.key});
  @override
  ConsumerState<TauBagdarApp> createState() => _TauBagdarAppState();
}

class _TauBagdarAppState extends ConsumerState<TauBagdarApp> {
  late final GoRouter _router = GoRouter(
    initialLocation: _startLocation(ref.read(profileProvider)),
    routes: [
      GoRoute(path: '/intro', builder: (_, __) => const IntroFlow()),
      GoRoute(
        path: '/register',
        builder: (_, s) => RegisterFlow(loginOnly: s.uri.queryParameters['login'] == '1'),
      ),
      GoRoute(path: '/app', builder: (_, __) => const MainShell()),
      GoRoute(path: '/chat', builder: (_, s) => ChatScreen(initialPrompt: s.extra as String?)),
      GoRoute(path: '/route/:id', builder: (_, s) => RouteDetailScreen(routeId: s.pathParameters['id']!)),
      GoRoute(path: '/trip/:id', builder: (_, s) => TripDetailScreen(tripId: s.pathParameters['id']!)),
      GoRoute(path: '/sos', builder: (_, __) => const SosScreen()),
      GoRoute(path: '/hike/:id', builder: (_, s) => HikeScreen(tripId: s.pathParameters['id']!)),
    ],
  );

  static String _startLocation(UserProfile p) {
    if (p.registered) return '/app';
    if (p.introSeen) return '/register';
    return '/intro';
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'TauBağdar',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        routerConfig: _router,
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru'), Locale('kk'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      );
}
