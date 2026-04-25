import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../models/user_model.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  User? _currentUser;
  User? get currentUser => _currentUser;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  AuthProvider() {
    // Listen to Supabase auth state changes
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      if (event == AuthChangeEvent.signedOut) {
        _currentUser = null;
        notifyListeners();
      } else if (event == AuthChangeEvent.signedIn) {
        _loadCurrentUser();
      }
    });
  }

  Future<void> _loadCurrentUser() async {
    final user = await _authService.getCurrentUser();
    _currentUser = user;
    notifyListeners();
  }

  Future<bool> checkLoginStatus() async {
    _isLoading = true;
    notifyListeners();

    final loggedIn = await _authService.isLoggedIn();
    if (loggedIn) {
      await _loadCurrentUser();
    }

    _isLoading = false;
    notifyListeners();
    return loggedIn;
  }

  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _authService.login(username, password);

    _isLoading = false;
    if (result == null) {
      await _loadCurrentUser();
      return true;
    } else {
      _error = result;
      notifyListeners();
      return false;
    }
  }

  Future<String?> register(
    String username,
    String password,
  ) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _authService.register(username, password);

    _isLoading = false;
    if (result == null) {
      final loggedIn = await _authService.isLoggedIn();
      if (loggedIn) {
        await _loadCurrentUser();
      }
    } else {
      _error = result;
    }

    notifyListeners();
    return result;
  }

  Future<void> logout() async {
    await _authService.logout();
    _currentUser = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
