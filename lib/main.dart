import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'services/notification_service.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/search_screen.dart';
import 'screens/friends_screen.dart';
import 'screens/home_screen.dart';

bool _isServerOnlySupabaseKey(String key) {
  if (key.startsWith('sb_secret_')) {
    return true;
  }

  final parts = key.split('.');
  if (parts.length != 3) {
    return false;
  }

  try {
    final payloadBytes = base64Url.decode(base64Url.normalize(parts[1]));
    final payload = jsonDecode(utf8.decode(payloadBytes));
    if (payload is Map<String, dynamic>) {
      return payload['role'] == 'service_role';
    }
  } catch (_) {
    // If parsing fails, treat it as a non-JWT key and continue.
  }

  return false;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final clientKey =
      dotenv.env['SUPABASE_PUBLISHABLE_KEY'] ?? dotenv.env['SUPABASE_ANON_KEY'];

  if (supabaseUrl == null || supabaseUrl.isEmpty) {
    throw StateError('Missing SUPABASE_URL in .env');
  }

  if (clientKey == null || clientKey.isEmpty) {
    throw StateError(
      'Missing SUPABASE_PUBLISHABLE_KEY (or SUPABASE_ANON_KEY fallback) in .env',
    );
  }

  if (_isServerOnlySupabaseKey(clientKey)) {
    throw StateError(
      'Server-only Supabase key detected in client config. Use publishable or anon key only.',
    );
  }

  await Supabase.initialize(url: supabaseUrl, anonKey: clientKey);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      navigatorKey: NotificationService.navigatorKey,
      title: 'Chat App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: themeProvider.themeMode,
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/search': (context) => const SearchScreen(),
        '/friends': (context) => const FriendsScreen(),
        '/home': (context) => const HomeScreen(),
      },
    );
  }
}
