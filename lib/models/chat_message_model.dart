class ChatMessage {
  final String id;
  final String senderId;
  final String? receiverId;
  final String content;
  final DateTime createdAt;
  final String? senderUsername;

  ChatMessage({
    required this.id,
    required this.senderId,
    this.receiverId,
    required this.content,
    required this.createdAt,
    this.senderUsername,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      senderId: json['sender_id'] as String,
      receiverId: json['receiver_id'] as String?,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      senderUsername: json['sender_username'] as String?,
    );
  }

  bool isMe(String currentUserId) => senderId == currentUserId;
}