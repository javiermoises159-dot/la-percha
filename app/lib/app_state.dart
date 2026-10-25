import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Account {
  const Account(
      {required this.username, required this.phone, required this.city});
  final String username;
  final String phone;
  final String city;
}

String digitsOf(String s) => s.replaceAll(RegExp(r'\D'), '');

/// Móvil venezolano, por ejemplo 0414-1234567 o +58 414 1234567.
bool isValidPhone(String s) => RegExp(r'^(58)?0?4\d{9}$').hasMatch(digitsOf(s));

/// Estado de la cuenta. En la etapa 2 se conectará a Firebase.
class AppState extends ChangeNotifier {
  Account? _saved;
  bool _signedIn = false;
  bool guest = false;
  bool loaded = false;

  Account? get account => _signedIn ? _saved : null;
  Account? get saved => _saved;

  bool hasSavedPhone(String phone) =>
      _saved != null && digitsOf(_saved!.phone) == digitsOf(phone);

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final u = p.getString('acct_u');
    if (u != null) {
      _saved = Account(
        username: u,
        phone: p.getString('acct_t') ?? '',
        city: p.getString('acct_c') ?? '',
      );
    }
    _signedIn = p.getBool('signed_in') ?? false;
    guest = p.getBool('guest') ?? false;
    loaded = true;
    notifyListeners();
  }

  Future<void> register(Account a) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('acct_u', a.username);
    await p.setString('acct_t', a.phone);
    await p.setString('acct_c', a.city);
    await p.setBool('signed_in', true);
    _saved = a;
    _signedIn = true;
    notifyListeners();
  }

  Future<void> signIn() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('signed_in', true);
    _signedIn = true;
    notifyListeners();
  }

  Future<void> signOut() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('signed_in', false);
    await p.setBool('guest', false);
    _signedIn = false;
    guest = false;
    notifyListeners();
  }

  Future<void> continueAsGuest() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('guest', true);
    guest = true;
    notifyListeners();
  }
}
