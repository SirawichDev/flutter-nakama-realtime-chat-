class User {
  final String id;
  final String username;
  final bool isOnline;

  User({
    required this.id,
    required this.username,
    this.isOnline = false,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? 'Unknown',
      isOnline: json['isOnline'] as bool? ?? false,
    );
  }
}

