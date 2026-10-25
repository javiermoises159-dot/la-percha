import 'package:flutter/material.dart';

import 'app_state.dart';
import 'theme.dart';

const _cities = [
  'Caracas', 'Valencia', 'Maracaibo', 'Barquisimeto', 'Maracay',
  'Puerto La Cruz', 'Mérida', 'San Cristóbal', 'Ciudad Guayana',
  'Isla de Margarita',
];

/// Hoja de registro e inicio de sesión (correo y contraseña).
Future<void> showAuthSheet(BuildContext context, AppState state,
    {bool login = false, String? message}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: AuthFlow(state: state, login: login, message: message),
    ),
  );
}

class AuthFlow extends StatefulWidget {
  const AuthFlow(
      {super.key, required this.state, this.login = false, this.message});
  final AppState state;
  final bool login;
  final String? message;

  @override
  State<AuthFlow> createState() => _AuthFlowState();
}

class _AuthFlowState extends State<AuthFlow> {
  late bool _login = widget.login;
  String? _error;
  bool _busy = false;
  bool _terms = false;
  final _user = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _city = TextEditingController();

  @override
  void initState() {
    super.initState();
    _error = widget.message;
  }

  @override
  void dispose() {
    _user.dispose();
    _email.dispose();
    _pass.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final pass = _pass.text;
    if (!isValidEmail(email)) {
      return setState(() => _error = 'Escribe un correo válido.');
    }
    if (pass.length < 6) {
      return setState(
          () => _error = 'La contraseña debe tener al menos 6 caracteres.');
    }
    if (!_login) {
      final u = _user.text.trim();
      if (!isValidUsername(u)) {
        return setState(() => _error =
            'El usuario debe tener 3 a 20 caracteres: letras, números, punto o guion bajo.');
      }
      if (_city.text.trim().length < 2) {
        return setState(() => _error = 'Indica tu ciudad.');
      }
      if (!_terms) {
        return setState(() => _error = 'Acepta los términos para continuar.');
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = _login
        ? await widget.state.signIn(email, pass)
        : await widget.state.signUp(
            email: email,
            password: pass,
            username: _user.text.trim(),
            city: _city.text.trim());
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _busy = false;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_login ? 'Iniciar sesión' : 'Crea tu cuenta',
              style: display(24, color: t.colorScheme.onSurface)),
          const SizedBox(height: 12),
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: context.chip,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_error!),
            ),
          if (!_login) ...[
            TextField(
              controller: _user,
              maxLength: 20,
              decoration: const InputDecoration(
                  labelText: 'Nombre de usuario',
                  hintText: 'Lo verán los demás'),
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Correo'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            obscureText: true,
            decoration: const InputDecoration(
                labelText: 'Contraseña', hintText: 'Mínimo 6 caracteres'),
          ),
          const SizedBox(height: 12),
          if (!_login) ...[
            Autocomplete<String>(
              optionsBuilder: (v) => _cities.where(
                  (c) => c.toLowerCase().contains(v.text.toLowerCase())),
              onSelected: (v) => _city.text = v,
              fieldViewBuilder: (ctx, controller, focus, onSubmit) {
                controller.addListener(() => _city.text = controller.text);
                return TextField(
                  controller: controller,
                  focusNode: focus,
                  decoration: const InputDecoration(
                      labelText: 'Ciudad', hintText: 'Valencia'),
                );
              },
            ),
            CheckboxListTile(
              value: _terms,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Acepto los términos y la privacidad'),
              onChanged: (v) => setState(() => _terms = v ?? false),
            ),
          ],
          const SizedBox(height: 8),
          FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy
                  ? 'Un momento…'
                  : (_login ? 'Entrar' : 'Crear cuenta'))),
          TextButton(
            onPressed: () => setState(() {
              _login = !_login;
              _error = null;
            }),
            child: Text(_login ? 'Crear una cuenta nueva' : 'Ya tengo cuenta'),
          ),
        ],
      ),
    );
  }
}
