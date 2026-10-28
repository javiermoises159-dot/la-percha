import 'package:flutter/material.dart';

import 'app_state.dart';
import 'info_pages.dart';
import 'nav.dart';
import 'theme.dart';

const _cities = [
  'Caracas',
  'Valencia',
  'Maracaibo',
  'Barquisimeto',
  'Maracay',
  'Puerto La Cruz',
  'Mérida',
  'San Cristóbal',
  'Ciudad Guayana',
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
  bool _codigoModo = false;
  final _codigo = TextEditingController();
  final _clave2 = TextEditingController();
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
    _codigo.dispose();
    _clave2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final pass = _pass.text;
    if (!isValidEmail(email)) {
      return setState(() => _error = 'Escribe un correo válido.');
    }
    if (pass.length < 6 || (!_login && pass.length < 8)) {
      return setState(() => _error = _login
          ? 'La contraseña debe tener al menos 6 caracteres.'
          : 'Usa una contraseña de al menos 8 caracteres.');
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

  Future<void> _olvide() async {
    final email = _email.text.trim();
    if (!isValidEmail(email)) {
      return setState(() => _error = 'Escribe tu correo arriba y vuelve a tocar "¿Olvidaste tu contraseña?".');
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await widget.state.pedirRecuperacion(email);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (err == null) {
        _codigoModo = true;
        _error = 'Te enviamos un código de 6 números a $email. Revisa también el spam.';
      } else {
        _error = err;
      }
    });
  }

  Future<void> _cambiarClave() async {
    final email = _email.text.trim();
    final cod = _codigo.text.trim();
    final nueva = _clave2.text;
    if (cod.length < 6) return setState(() => _error = 'Escribe el código de 6 números que llegó a tu correo.');
    if (nueva.length < 8) return setState(() => _error = 'Usa una contraseña de al menos 8 caracteres.');
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await widget.state.recuperarConCodigo(email, cod, nueva);
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop();
      avisoGlobal('Contraseña cambiada. Ya entraste a tu cuenta.');
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
          Text(_codigoModo ? 'Cambiar contraseña' : (_login ? 'Iniciar sesión' : 'Crea tu cuenta'),
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
            enabled: !_codigoModo,
            decoration: const InputDecoration(labelText: 'Correo'),
          ),
          if (_codigoModo) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _codigo,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(labelText: 'Código del correo', counterText: ''),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _clave2,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Contraseña nueva', hintText: 'Mínimo 8 caracteres'),
            ),
            const SizedBox(height: 16),
            FilledButton(
                onPressed: _busy ? null : _cambiarClave,
                child: Text(_busy ? 'Un momento…' : 'Cambiar contraseña')),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _codigoModo = false;
                        _error = null;
                      }),
              child: const Text('Volver'),
            ),
          ],
          if (!_codigoModo) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            obscureText: true,
            decoration: InputDecoration(
                labelText: 'Contraseña', hintText: _login ? null : 'Mínimo 8 caracteres'),
          ),
          const SizedBox(height: 12),
          if (!_login) ...[
            Autocomplete<String>(
              optionsBuilder: (v) => _cities
                  .where((c) => c.toLowerCase().contains(v.text.toLowerCase())),
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
              title: const Text('Tengo 18 años o más y acepto los términos y la privacidad'),
              onChanged: (v) => setState(() => _terms = v ?? false),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(spacing: 4, children: [
                TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const TermsPage())),
                  child: const Text('Leer los términos'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const InfoPage(
                          title: 'Política de privacidad', body: privacyText))),
                  child: const Text('Leer la privacidad'),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 8),
          FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy
                  ? 'Un momento…'
                  : (_login ? 'Entrar' : 'Crear cuenta'))),
          if (_login)
            TextButton(
              onPressed: _busy ? null : _olvide,
              child: const Text('¿Olvidaste tu contraseña?'),
            ),
          TextButton(
            onPressed: () => setState(() {
              _login = !_login;
              _error = null;
            }),
            child: Text(_login ? 'Crear una cuenta nueva' : 'Ya tengo cuenta'),
          ),
          if (widget.state.googleDisponible) ...[
            Row(children: [
              Expanded(child: Divider(color: context.line)),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text('o', style: TextStyle(color: context.muted))),
              Expanded(child: Divider(color: context.line)),
            ]),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      final e = await widget.state.signInGoogle();
                      if (mounted) setState(() {
                        _busy = false;
                        _error = e;
                      });
                    },
              icon: const _GoogleG(),
              label: const Text('Continuar con Google'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            ),
          ],
          ],
        ],
      ),
    );
  }
}


class _GoogleG extends StatelessWidget {
  const _GoogleG();
  @override
  Widget build(BuildContext context) => const Text('G',
      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF4285F4)));
}

/// Después de entrar con Google por primera vez: elegir usuario y ciudad.
class CompletarPerfilPage extends StatefulWidget {
  const CompletarPerfilPage({super.key, required this.state});
  final AppState state;
  @override
  State<CompletarPerfilPage> createState() => _CompletarPerfilPageState();
}

class _CompletarPerfilPageState extends State<CompletarPerfilPage> {
  final _user = TextEditingController();
  final _city = TextEditingController();
  bool _terms = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final u = _user.text.trim();
    if (!isValidUsername(u)) {
      return setState(() => _error = 'El usuario debe tener 3 a 20 caracteres: letras, números, punto o guion bajo.');
    }
    if (_city.text.trim().length < 2) return setState(() => _error = 'Indica tu ciudad.');
    if (!_terms) return setState(() => _error = 'Acepta los términos para continuar.');
    setState(() {
      _busy = true;
      _error = null;
    });
    final e = await widget.state.completarPerfil(u, _city.text.trim());
    if (mounted) setState(() {
      _busy = false;
      _error = e;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Último paso'), actions: [
          TextButton(onPressed: widget.state.signOut, child: const Text('Salir')),
        ]),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          Text('Elige cómo te verán en Pavito', style: display(22, color: context.ink)),
          const SizedBox(height: 6),
          Text('Tu nombre de usuario aparece en tus anuncios. Tu correo no se muestra a nadie.',
              style: TextStyle(color: context.muted, height: 1.4)),
          const SizedBox(height: 18),
          TextField(
              controller: _user,
              maxLength: 20,
              decoration: const InputDecoration(labelText: 'Nombre de usuario', hintText: 'closet.de.ana')),
          const SizedBox(height: 8),
          Autocomplete<String>(
            optionsBuilder: (v) => _cities.where((c) => c.toLowerCase().contains(v.text.toLowerCase())),
            onSelected: (v) => _city.text = v,
            fieldViewBuilder: (ctx, controller, focus, onSubmit) {
              controller.addListener(() => _city.text = controller.text);
              return TextField(
                  controller: controller,
                  focusNode: focus,
                  decoration: const InputDecoration(labelText: 'Ciudad', hintText: 'Valencia'));
            },
          ),
          CheckboxListTile(
            value: _terms,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Tengo 18 años o más y acepto los términos y la privacidad'),
            onChanged: (v) => setState(() => _terms = v ?? false),
          ),
          Wrap(spacing: 4, children: [
            TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TermsPage())),
                child: const Text('Leer los términos')),
            TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const InfoPage(title: 'Política de privacidad', body: privacyText))),
                child: const Text('Leer la privacidad')),
          ]),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!, style: const TextStyle(color: Color(0xFFB3261E))),
          ],
          const SizedBox(height: 12),
          FilledButton(onPressed: _busy ? null : _guardar, child: Text(_busy ? 'Un momento…' : 'Entrar a Pavito')),
        ]),
      );
}


/// Se abre al tocar el enlace del correo de recuperación: pone la contraseña nueva.
Future<void> mostrarNuevaClave(AppState state) async {
  final ctx = navKey.currentContext;
  if (ctx == null) return;
  final c = TextEditingController();
  String? error;
  bool busy = false;
  await showDialog<void>(
    context: ctx,
    barrierDismissible: false,
    builder: (dctx) => StatefulBuilder(
      builder: (dctx, setS) => AlertDialog(
        title: const Text('Nueva contraseña'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: c,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Contraseña nueva', hintText: 'Mínimo 8 caracteres'),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(error!, style: const TextStyle(color: Color(0xFFB3261E))),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.of(dctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    if (c.text.length < 8) {
                      setS(() => error = 'Usa una contraseña de al menos 8 caracteres.');
                      return;
                    }
                    setS(() {
                      busy = true;
                      error = null;
                    });
                    final e = await state.guardarNuevaClave(c.text);
                    if (e == null) {
                      if (dctx.mounted) Navigator.of(dctx).pop();
                      avisoGlobal('Contraseña cambiada. Ya puedes usar la app.');
                    } else {
                      setS(() {
                        busy = false;
                        error = e;
                      });
                    }
                  },
            child: Text(busy ? 'Guardando…' : 'Guardar'),
          ),
        ],
      ),
    ),
  );
  c.dispose();
}
