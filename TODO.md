# Chat App Implementation TODO

- [x] Update pubspec.yaml (add shared_preferences & provider)
- [x] Run flutter pub get
- [x] Create lib/models/user_model.dart
- [x] Create lib/services/auth_service.dart
- [x] Create lib/providers/auth_provider.dart
- [x] Create lib/screens/splash_screen.dart
- [x] Create lib/screens/login_screen.dart
- [x] Create lib/screens/register_screen.dart
- [x] Create lib/screens/home_screen.dart
- [x] Update lib/main.dart
- [x] Run on Windows to verify

# Dark Mode & Notifications TODO

- [x] Add notification support (custom in-app banners)
- [x] Create lib/providers/theme_provider.dart
- [x] Create lib/services/notification_service.dart
- [x] Update AndroidManifest.xml with notification permissions
- [x] Update lib/main.dart (MultiProvider + theme support)
- [x] Update lib/screens/home_screen.dart (theme toggle + notification button)
- [x] Update lib/screens/login_screen.dart (welcome back notification)
- [x] Update lib/screens/register_screen.dart (welcome notification)
- [x] Run on Windows to verify

# Supabase Integration TODO

- [x] Create .env with Supabase credentials
- [x] Update .gitignore to ignore .env
- [x] Add supabase_flutter + flutter_dotenv dependencies
- [x] Update lib/main.dart (initialize Supabase)
- [x] Rewrite lib/services/auth_service.dart (Supabase auth)
- [x] Update lib/providers/auth_provider.dart (auth state listener)
- [x] Create supabase_setup.sql
- [x] Run on Windows to verify

