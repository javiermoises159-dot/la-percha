import 'captcha.dart';
import 'config.dart';
import 'nav.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class Account {
  const Account(
      {required this.id,
      required this.username,
      required this.city,
      required this.email,
      this.isAdmin = false});
  final bool isAdmin;
  final String id;
  final String username;
  final String city;
  final String email;
}

bool isValidUsername(String s) => RegExp(r'^[A-Za-z0-9_.]{3,20}$').hasMatch(s);

bool isValidEmail(String s) =>
    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s.trim());

/// Estado de la sesión, conectado a Supabase.
class AppState extends ChangeNotifier {
  SupabaseClient get _db => Supabase.instance.client;

  Account? account;
  Set<String> favs = {};

  /// Precio de cada favorito cuando se guardó (para avisar si baja).
  Map<String, double> favPriceAt = {};
  bool guest = false;

  /// Entró (por ejemplo con Google) pero aún no eligió usuario y ciudad.
  bool sinPerfil = false;

  /// "Entrar con Google" solo aparece si está activado en Supabase.
  bool googleDisponible = false;
  bool loaded = false;
  StreamSubscription<AuthState>? _sub;

  Future<void> load() async {
    _sub = _db.auth.onAuthStateChange.listen((_) => refresh(), onError: (Object e) {
      final m = e is AuthException ? e.message : '$e';
      Future<void>.delayed(const Duration(seconds: 2), () => avisoGlobal('No se pudo entrar con Google: $m'));
    });
    _avisarErrorEnDireccion();
    _verGoogle();
    await refresh();
    loaded = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    final user = _db.auth.currentUser;
    if (user == null) {
      account = null;
      sinPerfil = false;
      favs = {};
      notifyListeners();
      return;
    }
    try {
      final row =
          await _db.from('profiles').select().eq('id', user.id).maybeSingle();
      sinPerfil = row == null;
      if (row != null) {
        account = Account(
          id: user.id,
          username: row['username'] as String,
          city: row['city'] as String,
          email: user.email ?? '',
          isAdmin: row['is_admin'] == true,
        );
        final f = await _db.from('favorites').select('listing_id, price_at');
        favs = {for (final r in f) r['listing_id'] as String};
        favPriceAt = {
          for (final r in f)
            if (r['price_at'] != null)
              r['listing_id'] as String: (r['price_at'] as num).toDouble()
        };
      }
    } catch (_) {
      // Sin conexión: se mantiene lo que ya había.
    }
    notifyListeners();
  }

  /// Devuelve null si todo salió bien, o el mensaje de error.
  static const _sinCaptcha =
      'No pudimos comprobar que no eres un robot. Revisa tu conexión e intenta de nuevo.';

  /// Token anti-bots: String si hay, null si está desactivado, false si falló.
  Future<Object?> _captcha() async {
    if (turnstileSiteKey.isEmpty) return null;
    final t = await obtenerCaptcha(turnstileSiteKey);
    return t ?? false;
  }

  Future<String?> signUp(
      {required String email,
      required String password,
      required String username,
      required String city}) async {
    // Si ya se creó la cuenta pero falló el perfil (por ejemplo, usuario reservado),
    // el reintento solo crea el perfil: no vuelve a registrar el correo.
    if (_db.auth.currentUser != null && account == null) {
      return completarPerfil(username, city);
    }
    try {
      final taken = await _db
          .from('profiles')
          .select('id')
          .eq('username', username)
          .maybeSingle();
      if (taken != null) return 'Ese nombre de usuario ya está en uso.';
      final captcha = await _captcha();
      if (captcha == false) return _sinCaptcha;
      final res = await _db.auth.signUp(
          email: email, password: password, captchaToken: captcha is String ? captcha : null);
      if (res.session == null || res.user == null) {
        return 'Revisa tu correo para confirmar la cuenta y luego inicia sesión.';
      }
      await _db
          .from('profiles')
          .insert({'id': res.user!.id, 'username': username, 'city': city});
      await refresh();
      return null;
    } on AuthException catch (e) {
      return _authMessage(e.message);
    } on PostgrestException catch (e) {
      return e.code == '23505'
          ? 'Ese nombre de usuario ya está en uso.'
          : e.message;
    } catch (_) {
      return 'No se pudo crear la cuenta. Revisa tu conexión.';
    }
  }

  /// Si Google o el servidor devolvieron un error en la dirección, se muestra.
  void _avisarErrorEnDireccion() {
    final u = Uri.base;
    Map<String, String> f = {};
    try {
      f = Uri.splitQueryString(u.fragment);
    } catch (_) {}
    final d = u.queryParameters['error_description'] ?? f['error_description'];
    if (d != null && d.isNotEmpty) {
      Future<void>.delayed(const Duration(seconds: 2), () => avisoGlobal('No se pudo entrar con Google: $d'));
    }
  }

  Future<void> _verGoogle() async {
    try {
      final r = await http.get(Uri.parse('$supabaseUrl/auth/v1/settings'), headers: {'apikey': supabaseKey});
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      googleDisponible = (j['external'] as Map?)?['google'] == true;
      notifyListeners();
    } catch (_) {}
  }

  /// Entrar o registrarse con Google. En la web la página va a Google y vuelve;
  /// en Android se abre el navegador y vuelve a la app.
  Future<String?> signInGoogle() async {
    try {
      await _db.auth.signInWithOAuth(OAuthProvider.google,
          redirectTo: kIsWeb ? '${Uri.base.origin}/' : 'com.pavito.pavito://login-callback');
      return null;
    } on AuthException catch (e) {
      return _authMessage(e.message);
    } catch (_) {
      return 'No se pudo abrir Google. Revisa tu conexión.';
    }
  }

  /// Tras entrar con Google: crea el perfil con el usuario y la ciudad elegidos.
  Future<String?> completarPerfil(String username, String city) async {
    final user = _db.auth.currentUser;
    if (user == null) return 'Vuelve a entrar.';
    try {
      final taken = await _db.from('profiles').select('id').eq('username', username).maybeSingle();
      if (taken != null) return 'Ese nombre de usuario ya está en uso.';
      await _db.from('profiles').insert({'id': user.id, 'username': username, 'city': city});
      await refresh();
      return null;
    } on PostgrestException catch (e) {
      return e.code == '23505' ? 'Ese nombre de usuario ya está en uso.' : e.message;
    } catch (_) {
      return 'No se pudo guardar. Revisa tu conexión.';
    }
  }

  Future<String?> signIn(String email, String password) async {
    try {
      final captcha = await _captcha();
      if (captcha == false) return _sinCaptcha;
      await _db.auth.signInWithPassword(
          email: email, password: password, captchaToken: captcha is String ? captcha : null);
      await refresh();
      if (account == null && !sinPerfil) {
        return 'Tu cuenta no tiene perfil. Escríbenos para ayudarte.';
      }
      return null;
    } on AuthException catch (e) {
      return _authMessage(e.message);
    } catch (_) {
      return 'No se pudo iniciar sesión. Revisa tu conexión.';
    }
  }

  String _authMessage(String m) {
    final t = m.toLowerCase();
    if (t.contains('invalid login')) return 'Correo o contraseña incorrectos.';
    if (t.contains('already registered'))
      return 'Ese correo ya tiene una cuenta.';
    if (t.contains('password'))
      return 'La contraseña debe tener al menos 6 caracteres.';
    if (t.contains('rate limit'))
      return 'Demasiados intentos. Espera unos minutos.';
    return m;
  }

  Future<void> signOut() async {
    await _db.auth.signOut();
    guest = false;
    account = null;
    favs = {};
    notifyListeners();
  }

  void continueAsGuest() {
    guest = true;
    notifyListeners();
  }

  Future<void> toggleFav(String listingId) async {
    final a = account;
    if (a == null) return;
    final had = favs.contains(listingId);
    if (had) {
      favs.remove(listingId);
    } else {
      favs.add(listingId);
    }
    notifyListeners();
    try {
      if (had) {
        await _db
            .from('favorites')
            .delete()
            .eq('user_id', a.id)
            .eq('listing_id', listingId);
      } else {
        await _db.from('favorites').insert({'listing_id': listingId});
      }
    } catch (_) {
      if (had) {
        favs.add(listingId);
      } else {
        favs.remove(listingId);
      }
      notifyListeners();
    }
  }
}

/// Estado único de la sesión, compartido por toda la app.
final appState = AppState();
