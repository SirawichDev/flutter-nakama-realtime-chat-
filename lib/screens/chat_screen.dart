import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nakama/src/api/proto/api/api.pb.dart' as api;
import '../services/nakama_service.dart';
import '../services/chat_storage_service.dart';
import '../models/chat_message.dart';
import 'dart:io';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final NakamaService _nakamaService = NakamaService();
  final ChatStorageService _storageService = ChatStorageService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();

  List<ChatMessage> _messages = [];
  bool _isConnected = false;
  bool _isLoading = false;
  String? _currentUsername;
  String? _channelId;

  // Pagination state
  String? _prevCursor; // Cursor for loading older messages
  bool _hasMoreMessages = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    // Add scroll listener for pagination
    _scrollController.addListener(_onScroll);
    // Wait for the widget tree to be built before showing dialog
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectToNakama();
    });
  }

  void _onScroll() {
    // Check if user scrolled to the top
    if (_scrollController.position.pixels <= 100 &&
        !_isLoadingMore &&
        _hasMoreMessages) {
      _loadMoreMessages();
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMoreMessages || _prevCursor == null) {
      return;
    }

    setState(() {
      _isLoadingMore = true;
    });

    try {
      print('Loading more messages with cursor: $_prevCursor');

      // Save current scroll position
      final currentScrollPosition = _scrollController.position.pixels;
      final currentMaxScrollExtent = _scrollController.position.maxScrollExtent;

      // Fetch older messages using prevCursor
      final result = await _nakamaService.fetchChannelHistory(
        limit: 30, // Load 30 more messages at a time
        forward: false,
        cursor: _prevCursor,
      );

      final olderMessages = result['messages'] as List<dynamic>;
      _prevCursor = result['prevCursor'] as String?;
      _hasMoreMessages = _prevCursor != null && _prevCursor!.isNotEmpty;

      print('Loaded ${olderMessages.length} more messages');
      print('Has more messages: $_hasMoreMessages');

      // Convert and download images
      final List<ChatMessage> newMessages = [];
      for (final nakamaMessage in olderMessages) {
        final message = ChatMessage.fromChannelMessage(nakamaMessage);

        // Download images for image messages
        if (message.isImage && message.imageUrl != null) {
          try {
            final imageData =
                await _nakamaService.downloadImageFromUrl(message.imageUrl!);
            message.imageData = imageData;
          } catch (e) {
            print('Error loading image for message ${message.id}: $e');
          }
        }

        newMessages.add(message);
      }

      // Insert older messages at the beginning
      setState(() {
        _messages.insertAll(0, newMessages);
        _isLoadingMore = false;
      });

      // Save to local storage
      if (_channelId != null) {
        for (final message in newMessages) {
          await _storageService.saveMessage(_channelId!, message);
        }
      }

      // Restore scroll position (adjust for new content height)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          final newMaxScrollExtent = _scrollController.position.maxScrollExtent;
          final scrollDelta = newMaxScrollExtent - currentMaxScrollExtent;
          _scrollController.jumpTo(currentScrollPosition + scrollDelta);
        }
      });
    } catch (e) {
      print('Error loading more messages: $e');
      setState(() {
        _isLoadingMore = false;
      });
      _showError('Failed to load more messages: $e');
    }
  }

  Future<void> _connectToNakama() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Show dialog to get username
      final username = await _showUsernameDialog();
      if (username == null || username.isEmpty) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      _currentUsername = username;

      // Initialize and authenticate
      await _nakamaService.initialize();
      final authenticated = await _nakamaService.authenticate(username);

      if (!authenticated) {
        print('Authentication failed for username: $username');
        _showError('Failed to authenticate. Check console logs for details.');
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Join chat channel
      final joined = await _nakamaService.joinChannel('general');

      if (!joined) {
        _showError('Failed to join channel');
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Get channel ID
      _channelId = _nakamaService.channelId;

      // Load messages: Try server first, fallback to local storage
      if (_channelId != null) {
        print('Loading chat history for channel: $_channelId');
        List<ChatMessage> loadedMessages = [];

        try {
          // 1. Try to fetch from Nakama server first (server-first approach)
          print('Fetching chat history from Nakama server...');
          final result = await _nakamaService.fetchChannelHistory(
            limit: 50, // Get last 50 messages initially
            forward: false, // Get older messages first
          );

          final historyMessages = result['messages'] as List<dynamic>;
          _prevCursor = result['prevCursor'] as String?;
          _hasMoreMessages = _prevCursor != null && _prevCursor!.isNotEmpty;

          print('Received ${historyMessages.length} messages from server');
          print('Has more messages: $_hasMoreMessages');

          // Convert Nakama messages to ChatMessage objects
          for (final nakamaMessage in historyMessages) {
            final message = ChatMessage.fromChannelMessage(nakamaMessage);

            // Download images for image messages
            if (message.isImage && message.imageUrl != null) {
              try {
                final imageData = await _nakamaService
                    .downloadImageFromUrl(message.imageUrl!);
                message.imageData = imageData;
              } catch (e) {
                print('Error loading image for message ${message.id}: $e');
              }
            }

            loadedMessages.add(message);
          }

          // Save fetched messages to local storage for offline access
          print('Saving ${loadedMessages.length} messages to local storage...');
          for (final message in loadedMessages) {
            await _storageService.saveMessage(_channelId!, message);
          }

          print(
              'Successfully loaded ${loadedMessages.length} messages from server');
        } catch (e) {
          // 2. If server fetch fails, fallback to local storage
          print('Failed to fetch from server: $e');
          print('Falling back to local storage...');

          try {
            loadedMessages = await _storageService.loadMessages(_channelId!);

            // Download images for image messages
            for (final message in loadedMessages) {
              if (message.isImage &&
                  message.imageUrl != null &&
                  message.imageData == null) {
                try {
                  final imageData = await _nakamaService
                      .downloadImageFromUrl(message.imageUrl!);
                  message.imageData = imageData;
                } catch (e) {
                  print('Error loading image for message ${message.id}: $e');
                }
              }
            }

            print(
                'Loaded ${loadedMessages.length} messages from local storage');
          } catch (storageError) {
            print('Failed to load from local storage: $storageError');
            // If both fail, start with empty messages
            loadedMessages = [];
          }
        }

        setState(() {
          _messages = loadedMessages;
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

  Future<String?> _showUsernameDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Enter Username'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Your username',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  void _handleIncomingMessage(api.ChannelMessage nakamaMessage) async {
    try {
      final message = ChatMessage.fromChannelMessage(nakamaMessage);

      // Check if message already exists (avoid duplicates)
      if (_messages.any((m) => m.id == message.id)) {
        print('Message ${message.id} already exists, skipping');
        return;
      }

      // If it's an image message, download the image from URL
      if (message.isImage && message.imageUrl != null) {
        final imageData =
            await _nakamaService.downloadImageFromUrl(message.imageUrl!);
        message.imageData = imageData;
      }

      setState(() {
        _messages.add(message);
      });

      // Save to local storage
      if (_channelId != null) {
        await _storageService.saveMessage(_channelId!, message);
      }

      // Scroll to bottom
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      print('Error handling message: $e');
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
    } catch (e) {
      _showError('Error sending message: $e');
    }
  }

  Future<void> _pickAndSendImage() async {
    try {
      print('Picking image from gallery...');
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );

      if (image == null) {
        print('No image selected');
        return;
      }

      print('Image selected: ${image.path}');
      final imageFile = File(image.path);

      if (!await imageFile.exists()) {
        _showError('Image file not found');
        return;
      }

      print('Sending image...');
      final success = await _nakamaService.sendImageMessage(imageFile);

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
    _nakamaService.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            Text(_isConnected ? 'Chat - $_currentUsername' : 'Connecting...'),
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
                      : Column(
                          children: [
                            // Loading indicator at the top when loading more
                            if (_isLoadingMore)
                              Container(
                                padding: const EdgeInsets.all(8.0),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    Text('Loading more messages...'),
                                  ],
                                ),
                              ),
                            // Messages list
                            Expanded(
                              child: ListView.builder(
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
                                        borderRadius:
                                            BorderRadius.circular(12.0),
                                      ),
                                      constraints: BoxConstraints(
                                        maxWidth:
                                            MediaQuery.of(context).size.width *
                                                0.7,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (!isMe)
                                            Text(
                                              message.username,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.grey.shade700,
                                              ),
                                            ),
                                          const SizedBox(height: 4),
                                          if (message.isImage &&
                                              message.imageData != null)
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8.0),
                                              child: Image.memory(
                                                message.imageData!,
                                                fit: BoxFit.cover,
                                              ),
                                            )
                                          else if (message.text != null)
                                            Text(
                                              message.text!,
                                              style:
                                                  const TextStyle(fontSize: 16),
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
                          ],
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
