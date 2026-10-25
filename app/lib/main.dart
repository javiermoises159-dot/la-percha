import 'package:flutter/material.dart';

import 'app_state.dart';
import 'home_shell.dart';
import 'logo.dart';
import 'theme.dart';
import 'welcome_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LaPerchaApp());
}

class LaPerchaApp extends StatefulWidget {
  const LaPerchaApp({super.key});

  @override
  State<LaPerchaApp> createState() => _LaPerchaAppState();
}

class _LaPerchaAppState extends State<LaPerchaApp> {
  final AppState _state = AppState();

  @override
  void initState() {
    super.initState();
    _state.load();
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
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

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: LogoMark(size: 72)));
  }
}
