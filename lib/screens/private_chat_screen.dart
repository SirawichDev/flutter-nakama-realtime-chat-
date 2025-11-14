import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nakama/src/api/proto/api/api.pb.dart' as api;
import 'package:path_provider/path_provider.dart';
import '../services/nakama_service.dart';
import '../services/chat_storage_service.dart';
import '../models/chat_message.dart';
import 'dart:io';

class PrivateChatScreen extends StatefulWidget {
  final String targetUserId;
  final String targetUsername;

  const PrivateChatScreen({
    super.key,
    required this.targetUserId,
    required this.targetUsername,
  });

  @override
  State<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

class _PrivateChatScreenState extends State<PrivateChatScreen> {
  final NakamaService _nakamaService = NakamaService();
  final ChatStorageService _storageService = ChatStorageService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();

  List<ChatMessage> _messages = [];
  bool _isConnected = false;
  bool _isLoading = false;
  String? _channelId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectToDirectMessage();
    });
  }

  Future<void> _connectToDirectMessage() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Check if already authenticated
      if (_nakamaService.session == null) {
        _showError('Not authenticated. Please go back and connect first.');
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Join direct message channel
      final joined =
          await _nakamaService.joinDirectMessage(widget.targetUserId);

      if (!joined) {
        _showError('Failed to start conversation');
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Get channel ID
      _channelId = _nakamaService.channelId;

      // Load previous messages from local storage
      if (_channelId != null) {
        print('Loading previous messages for channel: $_channelId');
        final previousMessages =
            await _storageService.loadMessages(_channelId!);

        // Download images for image messages
        for (final message in previousMessages) {
          if (message.isImage &&
              message.imageUrl != null &&
              message.imageData == null) {
            try {
              final imageData =
                  await _nakamaService.downloadImageFromUrl(message.imageUrl!);
              message.imageData = imageData;
            } catch (e) {
              print('Error loading image for message ${message.id}: $e');
            }
          }
        }

        setState(() {
          _messages = previousMessages;
        });

        // Scroll to bottom after loading
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController
                .jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
      }

      // Listen to messages
      _nakamaService.listenToMessages().listen((nakamaMessage) {
        _handleIncomingMessage(nakamaMessage);
      });

      setState(() {
        _isConnected = true;
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      print('Connection error: $e');
      print('Stack trace: $stackTrace');
      _showError('Connection error: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _handleIncomingMessage(api.ChannelMessage nakamaMessage) async {
    try {
      print('=== Incoming message ===');
      print('Message ID: ${nakamaMessage.messageId}');
      print('Sender ID: ${nakamaMessage.senderId}');
      print('Content: ${nakamaMessage.content}');

      final message = ChatMessage.fromChannelMessage(nakamaMessage);

      print(
          'Parsed message - isImage: ${message.isImage}, text: ${message.text}, imageUrl: ${message.imageUrl}');

      // Check if message already exists (avoid duplicates)
      if (_messages.any((m) => m.id == message.id)) {
        print('Message ${message.id} already exists, skipping');
        return;
      }

      // Add message to list first (will show loading indicator if it's an image)
      setState(() {
        _messages.add(message);
      });

      // Scroll to bottom immediately
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });

      // If it's an image message, download the image from URL
      if (message.isImage && message.imageUrl != null) {
        print('Downloading image from: ${message.imageUrl}');
        final imageData =
            await _nakamaService.downloadImageFromUrl(message.imageUrl!);

        if (imageData != null) {
          print('Image downloaded successfully, updating UI');
          setState(() {
            message.imageData = imageData;
          });
        } else {
          print('Failed to download image');
        }
      }

      // Save to local storage
      if (_channelId != null) {
        await _storageService.saveMessage(_channelId!, message);
      }
    } catch (e, stackTrace) {
      print('Error handling message: $e');
      print('Stack trace: $stackTrace');
    }
  }

  Future<void> _sendTextMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    try {
      final success = await _nakamaService.sendTextMessage(text);
      if (!success) {
        _showError('Failed to send message');
      }
      // Note: The message will be saved when we receive it back via listenToMessages
      // This ensures we save the message with the correct ID and timestamp from server
    } catch (e) {
      _showError('Error sending message: $e');
    }
  }

  Future<XFile?> _pickImage() async {
    print('Picking image from gallery...');
    final image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
    );

    if (image == null) {
      print('No image selected');
      return null;
    }

    print('Image selected: ${image.path}');
    return image;
  }

  Future<File?> _compressImage(File file) async {
    if (!await file.exists()) {
      _showError('Image file not found');
      return null;
    }

    final tempDir = await getTemporaryDirectory();
    final targetPath =
        '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.webp';

    print('Compressing image...');

    final compressedXFile = await FlutterImageCompress.compressAndGetFile(
      file.path,
      targetPath,
      quality: 80,
      minWidth: 1200,
      minHeight: 1200,
      format: CompressFormat.webp,
    );

    if (compressedXFile == null) {
      print('Image compression failed');
      return null;
    }

    print('Image compressed to: ${compressedXFile.path}');
    return File(compressedXFile.path);
  }

  Future<void> _pickAndSendImage() async {
    try {
      final image = await _pickImage();
      if (image == null) return;

      final File originalFile = File(image.path);
      File fileToSend = originalFile;

      // Attempt compression
      final File? compressed = await _compressImage(originalFile);

      if (compressed != null) {
        fileToSend = compressed;
        print('Using compressed image.');
      } else {
        print('Compression failed — using original image.');
      }

      print('Sending image...');
      final success = await _nakamaService.sendImageMessage(fileToSend);

      if (!success) {
        _showError('Failed to send image. Check console logs for details.');
      } else {
        print('Image sent successfully!');
      }
    } catch (e, stackTrace) {
      print('Error picking/sending image: $e');
      print('Stack trace: $stackTrace');
      _showError('Error picking image: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.targetUsername),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Messages list
                Expanded(
                  child: _messages.isEmpty
                      ? const Center(
                          child: Text('No messages yet. Start chatting!'),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(8.0),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final message = _messages[index];
                            final isMe =
                                message.userId == _nakamaService.userId;

                            return Align(
                              alignment: isMe
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.symmetric(
                                  vertical: 4.0,
                                  horizontal: 8.0,
                                ),
                                padding: const EdgeInsets.all(12.0),
                                decoration: BoxDecoration(
                                  color: isMe
                                      ? Colors.blue.shade100
                                      : Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(12.0),
                                ),
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.7,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (message.isImage)
                                      message.imageData != null
                                          ? ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8.0),
                                              child: Image.memory(
                                                message.imageData!,
                                                fit: BoxFit.cover,
                                                errorBuilder: (context, error,
                                                    stackTrace) {
                                                  return Container(
                                                    padding:
                                                        const EdgeInsets.all(
                                                            16),
                                                    child: Column(
                                                      children: [
                                                        Icon(
                                                          Icons.broken_image,
                                                          size: 48,
                                                          color: Colors
                                                              .grey.shade400,
                                                        ),
                                                        const SizedBox(
                                                            height: 8),
                                                        Text(
                                                          'Failed to display image',
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color: Colors
                                                                .grey.shade600,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                },
                                              ),
                                            )
                                          : Container(
                                              padding: const EdgeInsets.all(16),
                                              child: Column(
                                                children: [
                                                  const CircularProgressIndicator(),
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    'Loading image...',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color:
                                                          Colors.grey.shade600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            )
                                    else if (message.text != null)
                                      Text(
                                        message.text!,
                                        style: const TextStyle(fontSize: 16),
                                      ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${message.timestamp.hour}:${message.timestamp.minute.toString().padLeft(2, '0')}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                // Input area
                Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.shade300,
                        blurRadius: 4.0,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.image),
                        onPressed: _isConnected ? _pickAndSendImage : null,
                        tooltip: 'Send Image',
                      ),
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          decoration: const InputDecoration(
                            hintText: 'Type a message...',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          enabled: _isConnected,
                          onSubmitted: (_) => _sendTextMessage(),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: _isConnected ? _sendTextMessage : null,
                        tooltip: 'Send',
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
