class Profile {
  final String id;
  final String username;
  final String? avatarUrl;

  Profile({
    required this.id,
    required this.username,
    this.avatarUrl,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      username: json['username'] as String,
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}