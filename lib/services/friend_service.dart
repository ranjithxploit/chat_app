import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/friend_model.dart';

class FriendService {
  static const String _tokenKey = 'chatapp_jwt';

  SupabaseClient get _supabase => Supabase.instance.client;

  Future<String?> get _currentUserId async {
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

  Future<String?> sendFriendRequest(String receiverId) async {
    final senderId = await _currentUserId;
    if (senderId == null) return 'Not logged in.';

    if (senderId == receiverId) return 'Cannot send request to yourself.';

    final existing = await _supabase
        .from('friend_requests')
        .select('id, status')
        .or('sender_id.eq.$senderId,receiver_id.eq.$senderId')
        .eq('receiver_id', receiverId)
        .maybeSingle();

    if (existing != null) {
      final status = existing['status'] as String;
      if (status == 'pending') return 'Request already pending.';
      if (status == 'accepted') return 'Already friends.';
      if (status == 'rejected') {
        await _supabase.from('friend_requests').delete().eq('id', existing['id']);
      }
    }

    final reverse = await _supabase
        .from('friend_requests')
        .select('id, status')
        .eq('sender_id', receiverId)
        .eq('receiver_id', senderId)
        .maybeSingle();

    if (reverse != null) {
      final status = reverse['status'] as String;
      if (status == 'pending') {
        await _supabase.from('friend_requests').update({'status': 'accepted'}).eq('id', reverse['id']);
        await _addFriends(senderId, receiverId);
        await _addFriends(receiverId, senderId);
        return null;
      }
      if (status == 'rejected') {
        await _supabase.from('friend_requests').delete().eq('id', reverse['id']);
      }
    }

    await _supabase.from('friend_requests').insert({
      'sender_id': senderId,
      'receiver_id': receiverId,
      'status': 'pending',
    });

    return null;
  }

  Future<void> _addFriends(String userId, String friendId) async {
    await _supabase.from('friends').insert({
      'user_id': userId,
      'friend_id': friendId,
    });
  }

  Future<String?> acceptRequest(String requestId) async {
    final currentUserId = await _currentUserId;
    if (currentUserId == null) return 'Not logged in.';

    final request = await _supabase
        .from('friend_requests')
        .select('sender_id, receiver_id, status')
        .eq('id', requestId)
        .maybeSingle();

    if (request == null) return 'Request not found.';
    if (request['status'] != 'pending') return 'Request already handled.';

    await _supabase.from('friend_requests').update({'status': 'accepted'}).eq('id', requestId);

    await _addFriends(currentUserId, request['sender_id']);
    await _addFriends(request['sender_id'], currentUserId);

    return null;
  }

  Future<String?> rejectRequest(String requestId) async {
    await _supabase.from('friend_requests').update({'status': 'rejected'}).eq('id', requestId);
    return null;
  }

  Future<String?> cancelRequest(String requestId) async {
    await _supabase.from('friend_requests').delete().eq('id', requestId);
    return null;
  }

  Future<String?> unfriend(String friendId) async {
    final currentUserId = await _currentUserId;
    if (currentUserId == null) return 'Not logged in.';
    await _supabase.from('friends').delete().eq('user_id', currentUserId).eq('friend_id', friendId);
    await _supabase.from('friends').delete().eq('user_id', friendId).eq('friend_id', currentUserId);
    return null;
  }

  Future<List<FriendRequest>> getReceivedRequests() async {
    final currentUserId = await _currentUserId;
    if (currentUserId == null) return [];

    final result = await _supabase
        .from('friend_requests')
        .select('*, sender:profiles!sender_id(username, avatar_url)')
        .eq('receiver_id', currentUserId)
        .eq('status', 'pending')
        .order('created_at', ascending: false);

    return result.map((row) {
      final sender = row['sender'] as Map<String, dynamic>?;
      return FriendRequest(
        id: row['id'] as String,
        senderId: row['sender_id'] as String,
        receiverId: row['receiver_id'] as String,
        status: row['status'] as String,
        createdAt: DateTime.parse(row['created_at'] as String),
        senderUsername: sender?['username'] as String?,
        senderAvatarUrl: sender?['avatar_url'] as String?,
      );
    }).toList();
  }

  Future<List<FriendRequest>> getSentRequests() async {
    final currentUserId = await _currentUserId;
    if (currentUserId == null) return [];

    final result = await _supabase
        .from('friend_requests')
        .select('*, receiver:profiles!receiver_id(username, avatar_url)')
        .eq('sender_id', currentUserId)
        .eq('status', 'pending')
        .order('created_at', ascending: false);

    return result.map((row) {
      final receiver = row['receiver'] as Map<String, dynamic>?;
      return FriendRequest(
        id: row['id'] as String,
        senderId: row['sender_id'] as String,
        receiverId: row['receiver_id'] as String,
        status: row['status'] as String,
        createdAt: DateTime.parse(row['created_at'] as String),
        receiverUsername: receiver?['username'] as String?,
        receiverAvatarUrl: receiver?['avatar_url'] as String?,
      );
    }).toList();
  }

  Future<List<FriendRequest>> getAcceptedRequests() async {
    final currentUserId = await _currentUserId;
    if (currentUserId == null) return [];

    final result = await _supabase
        .from('friend_requests')
        .select('''
          id,
          sender_id,
          receiver_id,
          status,
          created_at,
          sender:profiles!sender_id(username, avatar_url),
          receiver:profiles!receiver_id(username, avatar_url)
        ''')
        .or('sender_id.eq.$currentUserId,receiver_id.eq.$currentUserId')
        .eq('status', 'accepted')
        .order('created_at', ascending: false);

    return result.map((row) {
      final sender = row['sender'] as Map<String, dynamic>?;
      final receiver = row['receiver'] as Map<String, dynamic>?;
      return FriendRequest(
        id: row['id'] as String,
        senderId: row['sender_id'] as String,
        receiverId: row['receiver_id'] as String,
        status: row['status'] as String,
        createdAt: DateTime.parse(row['created_at'] as String),
        senderUsername: sender?['username'] as String?,
        receiverUsername: receiver?['username'] as String?,
        senderAvatarUrl: sender?['avatar_url'] as String?,
        receiverAvatarUrl: receiver?['avatar_url'] as String?,
      );
    }).toList();
  }

  Future<List<Friend>> getFriends() async {
    final currentUserId = await _currentUserId;
    if (currentUserId == null) return [];

    final result = await _supabase
        .from('friends')
        .select('*, friend:profiles!friend_id(username, avatar_url)')
        .eq('user_id', currentUserId)
        .order('created_at', ascending: false);

    return result.map((row) {
      final friend = row['friend'] as Map<String, dynamic>?;
      return Friend(
        id: row['id'] as String,
        userId: row['user_id'] as String,
        friendId: row['friend_id'] as String,
        createdAt: DateTime.parse(row['created_at'] as String),
        friendUsername: friend?['username'] as String?,
        friendAvatarUrl: friend?['avatar_url'] as String?,
      );
    }).toList();
  }

  Future<String?> checkRequestStatus(String targetId) async {
    final currentUserId = await _currentUserId;
    if (currentUserId == null) return null;

    final req = await _supabase
        .from('friend_requests')
        .select('status')
        .or('and(sender_id.eq.$currentUserId,receiver_id.eq.$targetId),and(sender_id.eq.$targetId,receiver_id.eq.$currentUserId)')
        .maybeSingle();

    if (req == null) return null;
    return req['status'] as String;
  }
}