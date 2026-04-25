import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat_message_model.dart';

class ChatService {
  static const String _tokenKey = 'chatapp_jwt';

  SupabaseClient get _supabase => Supabase.instance.client;

  Future<String?> _getUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_tokenKey);
      if (token == null || token.isEmpty) return null;
      final session = jsonDecode(token) as Map<String, dynamic>;
      final userData = session['user'] as Map<String, dynamic>?;
      return userData?['id'] as String?;
    } catch (e) {
      return null;
    }
  }

  Future<String?> get currentUserId => _getUserId();

  Future<List<ChatMessage>> getMessages(String friendId) async {
    final currentUserId = await _getUserId();
    if (currentUserId == null) return [];

    final result = await _supabase
        .from('messages')
        .select('*, sender:profiles!sender_id(username)')
        .or('and(sender_id.eq.$currentUserId,receiver_id.eq.$friendId),and(sender_id.eq.$friendId,receiver_id.eq.$currentUserId)')
        .order('created_at', ascending: true);

    return result.map((row) {
      final sender = row['sender'] as Map<String, dynamic>?;
      return ChatMessage.fromJson({
        ...row,
        'receiver_id': null,
        'sender_username': sender?['username'] as String?,
      });
    }).toList();
  }

  Future<String?> sendMessage(String friendId, String content) async {
    final currentUserId = await _getUserId();
    if (currentUserId == null) return 'Not logged in.';

    await _supabase.from('messages').insert({
      'sender_id': currentUserId,
      'receiver_id': friendId,
      'content': content.trim(),
    });

    return null;
  }
}