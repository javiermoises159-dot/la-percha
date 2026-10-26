import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'config.dart';
import 'home_shell.dart';
import 'listing.dart';
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
      builder: (context, child) => _WideFrame(child: child ?? const SizedBox()),
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
              const Wordmark(size: 40),
              const SizedBox(height: 6),
              Text('Vende lo que ya no usas',
                  style: TextStyle(color: context.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// En pantallas muy anchas centra la app para que no se estire de borde a borde.
class _WideFrame extends StatelessWidget {
  const _WideFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 1500) return child;
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1500), child: child),
      ),
    );
  }
}
