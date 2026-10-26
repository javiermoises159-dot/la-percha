import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_page.dart';
import 'theme.dart';

SupabaseClient get _db => Supabase.instance.client;

/// Entrada al panel: el servidor solo trata a alguien como administrador si entró con
/// verificación en dos pasos (código de una app como Google Authenticator).
/// Esta pantalla la activa la primera vez y la pide cada vez que se abre el panel.
class AdminGate extends StatefulWidget {
  const AdminGate({super.key});
  @override
  State<AdminGate> createState() => _AdminGateState();
}

class _AdminGateState extends State<AdminGate> {
  bool? _listo; // null = comprobando
  String? _factorId;
  String? _qr;
  String? _secreto;
  final _codigo = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _comprobar();
  }

  @override
  void dispose() {
    _codigo.dispose();
    super.dispose();
  }

  Future<void> _comprobar() async {
    try {
      final falta = await _db.rpc('admin_necesita_2fa') as bool? ?? true;
      if (!falta) {
        if (mounted) setState(() => _listo = true);
        return;
      }
      final f = await _db.auth.mfa.listFactors();
      // Restos de intentos anteriores sin terminar.
      for (final x in f.all.where((x) => x.status == FactorStatus.unverified)) {
        try {
          await _db.auth.mfa.unenroll(x.id);
        } catch (_) {}
      }
      if (f.totp.isNotEmpty) {
        _factorId = f.totp.first.id;
      } else {
        final e = await _db.auth.mfa.enroll(
            issuer: 'Pavito',
            friendlyName: 'Pavito admin ${DateTime.now().millisecondsSinceEpoch}');
        _factorId = e.id;
        var q = e.totp?.qrCode ?? '';
        if (q.contains('%3C')) q = Uri.decodeComponent(q);
        final i = q.indexOf('<svg');
        _qr = i >= 0 ? q.substring(i) : null;
        _secreto = e.totp?.secret;
      }
      if (mounted) setState(() => _listo = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _listo = false;
          _error = 'No se pudo preparar la verificación: $e';
        });
      }
    }
  }

  Future<void> _verificar() async {
    final c = _codigo.text.replaceAll(RegExp(r'\D'), '');
    if (c.length != 6 || _factorId == null) {
      setState(() => _error = 'Escribe el código de 6 números de tu app.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _db.auth.mfa.challengeAndVerify(factorId: _factorId!, code: c);
      _codigo.clear();
      await _comprobar();
    } catch (_) {
      if (mounted) setState(() => _error = 'Código incorrecto o vencido. Prueba con el nuevo.');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_listo == true) return const AdminPage();
    return Scaffold(
      appBar: AppBar(title: const Text('Verificación en dos pasos')),
      body: _listo == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(20), children: [
              Text(
                  _qr != null
                      ? 'Activa la verificación en dos pasos'
                      : 'Escribe tu código de verificación',
                  style: display(22, color: context.ink)),
              const SizedBox(height: 8),
              Text(
                  _qr != null
                      ? 'El panel maneja dinero y datos bancarios. Sin este paso, aunque alguien robe tu contraseña no podrá entrar. '
                          'Abre Google Authenticator (o Microsoft Authenticator), toca "+", escanea este código y escribe los 6 números.'
                      : 'Abre tu app de autenticación y escribe los 6 números que muestra para Pavito.',
                  style: TextStyle(color: context.muted, height: 1.4)),
              if (_qr != null) ...[
                const SizedBox(height: 16),
                Center(
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(10),
                    child: SvgPicture.string(_qr!, width: 200, height: 200),
                  ),
                ),
                if (_secreto != null) ...[
                  const SizedBox(height: 10),
                  Text('¿No puedes escanear? Escribe esta clave en la app:',
                      style: TextStyle(color: context.muted, fontSize: 13)),
                  Row(children: [
                    Expanded(
                        child: SelectableText(_secreto!,
                            style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1))),
                    IconButton(
                        tooltip: 'Copiar',
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () => Clipboard.setData(ClipboardData(text: _secreto!))),
                  ]),
                ],
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _codigo,
                keyboardType: TextInputType.number,
                maxLength: 6,
                autofocus: true,
                style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.w700),
                decoration: const InputDecoration(labelText: 'Código de 6 números', counterText: ''),
                onSubmitted: (_) => _verificar(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Color(0xFFB3261E))),
              ],
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: _busy ? null : _verificar,
                  child: Text(_busy ? 'Comprobando…' : 'Verificar y entrar')),
            ]),
    );
  }
}
