import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'config.dart';
import 'home_shell.dart';
import 'listing.dart';
import 'logo.dart';
import 'theme.dart';
import 'welcome_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  runApp(const LaPerchaApp());
}

class LaPerchaApp extends StatefulWidget {
  const LaPerchaApp({super.key});

  @override
  State<LaPerchaApp> createState() => _LaPerchaAppState();
}

class _LaPerchaAppState extends State<LaPerchaApp> {
  final AppState _state = appState;

  @override
  void initState() {
    super.initState();
    _state.load();
    listingsStore.load();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'La Percha',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      themeMode: ThemeMode.light,
      home: ListenableBuilder(
        listenable: _state,
        builder: (context, _) {
          if (!_state.loaded) return const _Splash();
          if (_state.account == null && !_state.guest) {
            return WelcomeScreen(state: _state);
          }
          return HomeShell(state: _state);
        },
      ),
    );
  }
}

/// Pantalla de carga: el logo aparece con un pequeño efecto.
class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.85, end: 1),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutBack,
          builder: (context, v, child) => Opacity(
            opacity: v.clamp(0.0, 1.0),
            child: Transform.scale(scale: v, child: child),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LogoMark(size: 88),
              const SizedBox(height: 16),
              Text('La Percha',
                  style: display(30,
                      color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 6),
              Text('Dale otra vida a tu ropa',
                  style: TextStyle(color: context.muted)),
            ],
          ),
        ),
      ),
    );
  }
}
