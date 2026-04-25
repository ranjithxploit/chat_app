import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/user_model.dart' as models;

class AuthService {
  static const String _defaultAdminUrl = 'http://localhost:8787';
  static const String _adminTokenKey = 'ADMIN_API_TOKEN';
  static const String _tokenKey = 'chatapp_jwt';

  String? _adminApiToken;

  String _getAdminUrl() {
    final configuredUrl = dotenv.env['ADMIN_API_URL']?.trim();
    if (configuredUrl != null && configuredUrl.isNotEmpty) {
      return configuredUrl.replaceAll(RegExp(r'/$'), '');
    }
    return _defaultAdminUrl;
  }

  String _networkErrorMessage(Object error) {
    final adminUrl = _getAdminUrl();
    final usingLocalhost =
        adminUrl.contains('localhost') || adminUrl.contains('127.0.0.1');

    if (usingLocalhost) {
      return 'Network error: app is pointing to local server ($adminUrl). '
          'For other devices, set ADMIN_API_URL to your deployed admin API.';
    }

    return 'Network error: $error\nTarget API: $adminUrl';
  }

  String _getAdminToken() {
    if (_adminApiToken != null) return _adminApiToken!;
    _adminApiToken =
        dotenv.env[_adminTokenKey] ?? dotenv.env['ADMIN_TOKEN'] ?? '';
    return _adminApiToken!;
  }

  Future<Map<String, String>> _adminHeaders() async {
    return {
      'Content-Type': 'application/json',
      'x-admin-token': _getAdminToken(),
    };
  }

  Future<String?> _storeJwt(
    String token,
    String userId,
    String username,
  ) async {
    try {
      final expiresAt = DateTime.now().add(const Duration(days: 7));
      final session = {
        'access_token': token,
        'token_type': 'Bearer',
        'expires_in': 604800,
        'expires_at': expiresAt.toUtc().toIso8601String(),
        'refresh_token': token,
        'user': {
          'id': userId,
          'aud': 'authenticated',
          'role': 'authenticated',
          'email': '',
          'app_metadata': {'provider': 'chatapp'},
          'user_metadata': {'username': username},
        },
      };

      await SharedPreferences.getInstance().then(
        (prefs) => prefs.setString(_tokenKey, jsonEncode(session)),
      );

      return token;
    } catch (e) {
      return null;
    }
  }

  Future<void> _clearJwt() async {
    try {
      SharedPreferences.getInstance().then((prefs) => prefs.remove(_tokenKey));
    } catch (_) {}
  }

  Future<String?> register(String username, String password) async {
    if (username.isEmpty || password.isEmpty) {
      return 'Username and password are required.';
    }

    final normalizedUsername = username.trim();

    if (normalizedUsername.length < 3) {
      return 'Username must be at least 3 characters.';
    }

    if (normalizedUsername.length > 64) {
      return 'Username must be 64 characters or less.';
    }

    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(normalizedUsername)) {
      return 'Username can only contain letters, numbers, and underscores.';
    }

    try {
      final response = await http.post(
        Uri.parse('${_getAdminUrl()}/auth/register'),
        headers: await _adminHeaders(),
        body: '{"username":"$normalizedUsername","password":"$password"}',
      );

      if (response.statusCode == 409) {
        return 'Username is already taken.';
      }

      if (response.statusCode == 400) {
        final body = response.body.toLowerCase();
        if (body.contains('rate') || body.contains('too many')) {
          return 'Rate limit reached. Wait a few minutes.';
        }
        return 'Registration failed. Check your details.';
      }

      if (response.statusCode != 201) {
        return 'Server error (${response.statusCode}).';
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final token = data['token'] as String?;
      final userData = data['user'] as Map<String, dynamic>?;
      if (token == null || userData == null) {
        return 'Invalid server response.';
      }

      final userId = userData['id'] as String;
      final storedUsername = userData['username'] as String;

      await _storeJwt(token, userId, storedUsername);

      return null;
    } on SocketException catch (e) {
      return _networkErrorMessage(e.message);
    } on http.ClientException catch (e) {
      return _networkErrorMessage(e.message);
    } catch (e) {
      return 'An unexpected error occurred: $e';
    }
  }

  Future<String?> login(String username, String password) async {
    if (username.isEmpty || password.isEmpty) {
      return 'Username and password are required.';
    }

    try {
      final normalizedUsername = username.trim();

      final response = await http.post(
        Uri.parse('${_getAdminUrl()}/auth/login'),
        headers: await _adminHeaders(),
        body: '{"username":"$normalizedUsername","password":"$password"}',
      );

      if (response.statusCode == 401) {
        return 'Invalid username or password.';
      }

      if (response.statusCode != 200) {
        return 'Server error (${response.statusCode}).';
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final token = data['token'] as String?;
      final userData = data['user'] as Map<String, dynamic>?;
      if (token == null || userData == null) {
        return 'Invalid server response.';
      }

      final userId = userData['id'] as String;
      final storedUsername = userData['username'] as String;

      await _storeJwt(token, userId, storedUsername);

      return null;
    } on SocketException catch (e) {
      return _networkErrorMessage(e.message);
    } on http.ClientException catch (e) {
      return _networkErrorMessage(e.message);
    } catch (e) {
      return 'An unexpected error occurred: $e';
    }
  }

  Future<void> logout() async {
    await _clearJwt();
  }

  Future<bool> isLoggedIn() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_tokenKey);
      if (token == null || token.isEmpty) return false;

      final session = jsonDecode(token) as Map<String, dynamic>;
      final expiresAt = session['expires_at'] as String?;
      if (expiresAt != null) {
        final expiry = DateTime.tryParse(expiresAt);
        if (expiry != null && expiry.isBefore(DateTime.now())) {
          _clearJwt();
          return false;
        }
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<models.User?> getCurrentUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_tokenKey);
      if (token == null || token.isEmpty) return null;

      final session = jsonDecode(token) as Map<String, dynamic>;
      final userData = session['user'] as Map<String, dynamic>?;
      final username = userData?['user_metadata']?['username'] as String?;

      if (username != null) {
        return models.User(username: username, password: '');
      }

      return null;
    } catch (e) {
      return null;
    }
  }
}
