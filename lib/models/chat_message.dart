import 'dart:convert';
import 'dart:typed_data';
import 'package:nakama/src/api/proto/api/api.pb.dart' as api;

class ChatMessage {
  final String id;
  final String userId;
  final String username;
  final String? text;
  final String? imageId; // Deprecated - use imageUrl instead
  final String? imageUrl; // URL to download the image
  final String? objectKey; // Minio object key
  final DateTime timestamp;
  final bool isImage;
  Uint8List? imageData;

  ChatMessage({
    required this.id,
    required this.userId,
    required this.username,
    this.text,
    this.imageId,
    this.imageUrl,
    this.objectKey,
    required this.timestamp,
    this.isImage = false,
    this.imageData,
  });

  factory ChatMessage.fromChannelMessage(api.ChannelMessage nakamaMessage) {
    // Parse the content JSON string
    final contentStr = nakamaMessage.content;
    Map<String, dynamic> content;
    try {
      content = jsonDecode(contentStr) as Map<String, dynamic>;
    } catch (e) {
      content = {};
    }

    final isImage = content['type'] == 'image';

    // Parse timestamp
    DateTime timestamp;
    try {
      if (nakamaMessage.hasCreateTime()) {
        // createTime is a Timestamp protobuf object
        final ts = nakamaMessage.createTime;
        timestamp = DateTime.fromMillisecondsSinceEpoch(
          ts.seconds.toInt() * 1000 + (ts.nanos ~/ 1000000),
        );
      } else {
        timestamp = DateTime.now();
      }
    } catch (e) {
      timestamp = DateTime.now();
    }

    return ChatMessage(
      id: nakamaMessage.messageId,
      userId: nakamaMessage.senderId,
      username: nakamaMessage.username.isEmpty ? 'Unknown' : nakamaMessage.username,
      text: isImage ? null : content['message'] as String?,
      imageId: isImage ? content['imageId'] as String? : null, // backward compatibility
      imageUrl: isImage ? content['imageUrl'] as String? : null,
      objectKey: isImage ? content['objectKey'] as String? : null,
      timestamp: timestamp,
      isImage: isImage,
    );
  }
}
