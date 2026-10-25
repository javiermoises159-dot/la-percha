import 'package:flutter/material.dart';

import 'app_state.dart';
import 'theme.dart';

const _cities = [
  'Caracas', 'Valencia', 'Maracaibo', 'Barquisimeto', 'Maracay',
  'Puerto La Cruz', 'Mérida', 'San Cristóbal', 'Ciudad Guayana',
  'Isla de Margarita',
];

/// Hoja de registro e inicio de sesión.
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
  int _step = 1;
  String? _error;
  bool _terms = false;
  final _user = TextEditingController();
  final _tel = TextEditingController();
  final _city = TextEditingController();
  final _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    _error = widget.message;
  }

  @override
  void dispose() {
    _user.dispose();
    _tel.dispose();
    _city.dispose();
    _code.dispose();
    super.dispose();
  }

  void _next() {
    final tel = _tel.text.trim();
    if (!_login) {
      final u = _user.text.trim();
      if (u.length < 3 || u.length > 20) {
        return setState(() =>
            _error = 'El nombre de usuario debe tener entre 3 y 20 caracteres.');
      }
      if (!isValidPhone(tel)) {
        return setState(() =>
            _error = 'Escribe un móvil venezolano, por ejemplo 0414-1234567.');
      }
      if (_city.text.trim().isEmpty) {
        return setState(() => _error = 'Indica tu ciudad.');
      }
      if (!_terms) {
        return setState(() => _error = 'Acepta los términos para continuar.');
      }
    } else {
      if (!isValidPhone(tel)) {
        return setState(() =>
            _error = 'Escribe un móvil venezolano, por ejemplo 0414-1234567.');
      }
      if (!widget.state.hasSavedPhone(tel)) {
        return setState(() => _error =
            'No encontramos una cuenta con ese teléfono en este dispositivo. Crea una cuenta nueva.');
      }
    }
    setState(() {
      _error = null;
      _step = 2;
    });
  }

  Future<void> _verify() async {
    // TODO(etapa 2): reemplazar por verificación SMS con Firebase Auth.
    if (_code.text.trim() != '123456') {
      return setState(
          () => _error = 'El código no coincide. En la prueba es 123456.');
    }
    if (_login) {
      await widget.state.signIn();
    } else {
      await widget.state.register(Account(
        username: _user.text.trim(),
        phone: _tel.text.trim(),
        city: _city.text.trim(),
      ));
    }
    if (mounted) Navigator.of(context).pop();
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
          if (_step == 1) ..._stepOne(context) else ..._stepTwo(context),
        ],
      ),
    );
  }

  List<Widget> _stepOne(BuildContext context) {
    return [
      if (!_login) ...[
        TextField(
          controller: _user,
          maxLength: 20,
          decoration: const InputDecoration(
              labelText: 'Nombre de usuario', hintText: 'Lo verán los demás'),
        ),
        const SizedBox(height: 8),
      ],
      TextField(
        controller: _tel,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(
            labelText: 'Teléfono móvil', hintText: '0414-1234567'),
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
          onPressed: _next,
          child: Text(_login ? 'Enviar código' : 'Continuar')),
      TextButton(
        onPressed: () => setState(() {
          _login = !_login;
          _error = null;
        }),
        child: Text(_login ? 'Crear una cuenta nueva' : 'Ya tengo cuenta'),
      ),
    ];
  }

  List<Widget> _stepTwo(BuildContext context) {
    return [
      Text('Enviamos un código de 6 dígitos al ${_tel.text.trim()}.'),
      const SizedBox(height: 12),
      TextField(
        controller: _code,
        keyboardType: TextInputType.number,
        maxLength: 6,
        decoration:
            const InputDecoration(labelText: 'Código', hintText: '123456'),
      ),
      Text('Código de prueba: 123456. En la app real llegará por SMS.',
          style: TextStyle(color: context.muted, fontSize: 13)),
      const SizedBox(height: 12),
      FilledButton(onPressed: _verify, child: const Text('Verificar')),
      TextButton(
        onPressed: () => setState(() {
          _step = 1;
          _error = null;
        }),
        child: const Text('Cambiar teléfono'),
      ),
    ];
  }
}
