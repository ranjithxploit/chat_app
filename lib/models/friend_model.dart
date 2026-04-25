class FriendRequest {
  final String id;
  final String senderId;
  final String receiverId;
  final String status;
  final DateTime createdAt;
  final String? senderUsername;
  final String? receiverUsername;
  final String? senderAvatarUrl;
  final String? receiverAvatarUrl;

  FriendRequest({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.status,
    required this.createdAt,
    this.senderUsername,
    this.receiverUsername,
    this.senderAvatarUrl,
    this.receiverAvatarUrl,
  });

  factory FriendRequest.fromJson(Map<String, dynamic> json) {
    return FriendRequest(
      id: json['id'] as String,
      senderId: json['sender_id'] as String,
      receiverId: json['receiver_id'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      senderUsername: json['sender_username'] as String?,
      receiverUsername: json['receiver_username'] as String?,
      senderAvatarUrl: json['sender_avatar_url'] as String?,
      receiverAvatarUrl: json['receiver_avatar_url'] as String?,
    );
  }
}

class Friend {
  final String id;
  final String userId;
  final String friendId;
  final DateTime createdAt;
  final String? friendUsername;
  final String? friendAvatarUrl;

  Friend({
    required this.id,
    required this.userId,
    required this.friendId,
    required this.createdAt,
    this.friendUsername,
    this.friendAvatarUrl,
  });

  factory Friend.fromJson(Map<String, dynamic> json) {
    return Friend(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      friendId: json['friend_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      friendUsername: json['friend_username'] as String?,
      friendAvatarUrl: json['friend_avatar_url'] as String?,
    );
  }
}