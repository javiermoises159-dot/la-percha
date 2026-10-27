import 'captcha.dart';
import 'config.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
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
  bool loaded = false;
  StreamSubscription<AuthState>? _sub;

  Future<void> load() async {
    _sub = _db.auth.onAuthStateChange.listen((_) => refresh());
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
      favs = {};
      notifyListeners();
      return;
    }
    try {
      final row =
          await _db.from('profiles').select().eq('id', user.id).maybeSingle();
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

  Future<String?> signIn(String email, String password) async {
    try {
      final captcha = await _captcha();
      if (captcha == false) return _sinCaptcha;
      await _db.auth.signInWithPassword(
          email: email, password: password, captchaToken: captcha is String ? captcha : null);
      await refresh();
      if (account == null) {
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
