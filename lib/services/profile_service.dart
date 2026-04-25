import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile_model.dart';

class ProfileService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<Profile?> searchByUsername(String query) async {
    if (query.trim().isEmpty) return null;

    final normalizedQuery = query.trim().toLowerCase();

    final result = await _supabase
        .from('profiles')
        .select('id, username, avatar_url')
        .ilike('username', normalizedQuery)
        .maybeSingle();

    if (result == null) return null;
    return Profile.fromJson(result);
  }

  Future<Profile?> getById(String id) async {
    final result = await _supabase
        .from('profiles')
        .select('id, username, avatar_url')
        .eq('id', id)
        .maybeSingle();

    if (result == null) return null;
    return Profile.fromJson(result);
  }
}