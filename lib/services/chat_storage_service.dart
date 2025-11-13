import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';

/// Service for storing and retrieving chat messages from local storage
class ChatStorageService {
  static final ChatStorageService _instance = ChatStorageService._internal();
  factory ChatStorageService() => _instance;
  ChatStorageService._internal();

  static const String _messagesPrefix = 'chat_messages_';
  static const int _maxMessagesPerChat = 1000; // Limit messages per chat

  /// Get storage key for a chat channel
  String _getStorageKey(String channelId) {
    return '$_messagesPrefix$channelId';
  }

  /// Save a message to local storage
  Future<void> saveMessage(String channelId, ChatMessage message) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getStorageKey(channelId);

      // Get existing messages
      final messagesJson = prefs.getStringList(key) ?? [];

      // Convert message to JSON
      final messageJson = _messageToJson(message);

      // Add new message
      messagesJson.add(messageJson);

      // Keep only the most recent messages
      if (messagesJson.length > _maxMessagesPerChat) {
        messagesJson.removeRange(0, messagesJson.length - _maxMessagesPerChat);
      }

      // Save back to storage
      await prefs.setStringList(key, messagesJson);

      print('Saved message to local storage: ${message.id}');
    } catch (e) {
      print('Error saving message to local storage: $e');
    }
  }

  /// Load all messages for a channel from local storage
  Future<List<ChatMessage>> loadMessages(String channelId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getStorageKey(channelId);

      final messagesJson = prefs.getStringList(key) ?? [];

      final messages = messagesJson
          .map((jsonStr) => _messageFromJson(jsonStr))
          .where((msg) => msg != null)
          .cast<ChatMessage>()
          .toList();

      // Sort by timestamp
      messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      print(
          'Loaded ${messages.length} messages from local storage for channel: $channelId');
      return messages;
    } catch (e) {
      print('Error loading messages from local storage: $e');
      return [];
    }
  }

  /// Clear all messages for a channel
  Future<void> clearMessages(String channelId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getStorageKey(channelId);
      await prefs.remove(key);
      print('Cleared messages for channel: $channelId');
    } catch (e) {
      print('Error clearing messages: $e');
    }
  }

  /// Clear all stored messages (for all channels)
  Future<void> clearAllMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys =
          prefs.getKeys().where((key) => key.startsWith(_messagesPrefix));
      for (final key in keys) {
        await prefs.remove(key);
      }
      print('Cleared all stored messages');
    } catch (e) {
      print('Error clearing all messages: $e');
    }
  }

  /// Convert ChatMessage to JSON string
  String _messageToJson(ChatMessage message) {
    final map = {
      'id': message.id,
      'userId': message.userId,
      'username': message.username,
      'text': message.text,
      'imageId': message.imageId,
      'imageUrl': message.imageUrl,
      'objectKey': message.objectKey,
      'timestamp': message.timestamp.toIso8601String(),
      'isImage': message.isImage,
      // Note: imageData is not saved to avoid large storage usage
      // It will be downloaded again when needed
    };
    return jsonEncode(map);
  }

  /// Convert JSON string to ChatMessage
  ChatMessage? _messageFromJson(String jsonStr) {
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;

      return ChatMessage(
        id: map['id'] as String,
        userId: map['userId'] as String,
        username: map['username'] as String,
        text: map['text'] as String?,
        imageId: map['imageId'] as String?,
        imageUrl: map['imageUrl'] as String?,
        objectKey: map['objectKey'] as String?,
        timestamp: DateTime.parse(map['timestamp'] as String),
        isImage: map['isImage'] as bool? ?? false,
        // imageData will be null - will be downloaded when needed
      );
    } catch (e) {
      print('Error parsing message from JSON: $e');
      return null;
    }
  }

  /// Get list of all channel IDs that have stored messages
  Future<List<String>> getAllChannelIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs
          .getKeys()
          .where((key) => key.startsWith(_messagesPrefix))
          .map((key) => key.substring(_messagesPrefix.length))
          .toList();
      return keys;
    } catch (e) {
      print('Error getting channel IDs: $e');
      return [];
    }
  }
}
