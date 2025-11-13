import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/foundation.dart'
    show consolidateHttpClientResponseBytes, kIsWeb;
import 'package:nakama/nakama.dart';
import 'package:nakama/src/api/proto/api/api.pb.dart' as api;
import 'package:device_info_plus/device_info_plus.dart';

class NakamaService {
  static final NakamaService _instance = NakamaService._internal();
  factory NakamaService() => _instance;
  NakamaService._internal();

  NakamaBaseClient? _client;
  NakamaWebsocketClient? _socketClient;
  Session? _session;
  String? _userId;
  String? _username;

  String get host {
    if (Platform.isAndroid) {
      return '10.0.2.2'; // Android emulator special IP for host machine
    } else if (Platform.isIOS) {
      return '127.0.0.1'; // iOS simulator can use localhost
    } else {
      return '127.0.0.1'; // Default for other platforms
    }
  }

  final int port = 7350;
  final String serverKey = 'defaultkey';
  final bool ssl = false;

  String? _channelId;
  String? _channelName;
  StreamSubscription<ChannelMessage>? _messageSubscription;
  StreamSubscription<ChannelPresenceEvent>? _presenceSubscription;

  // Track users from presence events
  final Map<String, String> _users = {}; // userId -> username

  // Stream controller for users list updates
  final _usersStreamController =
      StreamController<List<Map<String, String>>>.broadcast();

  /// Stream of users list updates
  Stream<List<Map<String, String>>> get usersStream =>
      _usersStreamController.stream;

  NakamaBaseClient? get client => _client;
  Session? get session => _session;
  String? get userId => _userId;
  String? get username => _username;
  String? get channelId => _channelId;

  /// Initialize Nakama client
  Future<void> initialize() async {
    print('Initializing Nakama client with host: $host, port: $port');
    _client = getNakamaClient(
      host: host,
      ssl: ssl,
      serverKey: serverKey,
      httpPort: port,
      grpcPort: 7349,
    );
    print('Nakama client initialized');
  }

  /// Initialize WebSocket client
  Future<void> _initializeSocket() async {
    if (_session == null) {
      throw Exception('Not authenticated');
    }

    print('Initializing WebSocket client with host: $host, port: 7350');
    _socketClient = NakamaWebsocketClient.init(
      host: host,
      ssl: ssl,
      port: 7350,
      token: _session!.token,
      onError: (error) {
        print('WebSocket error: $error');
      },
    );
    print('WebSocket client initialized');
  }

  Future<String> _getDeviceId(String username) async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      String? emulatorSerial;
      String deviceBaseId;

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        // Use serial number (unique per emulator) or Android ID as base
        emulatorSerial = androidInfo.serialNumber;
        deviceBaseId = androidInfo.id; // Android ID
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceBaseId = iosInfo.identifierForVendor ??
            'ios-device-${DateTime.now().millisecondsSinceEpoch}';
      } else {
        deviceBaseId = 'device-${DateTime.now().millisecondsSinceEpoch}';
      }

      // Generate a unique UUID-like string for this session
      final random = Random();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final randomPart1 = random.nextInt(999999).toString().padLeft(6, '0');
      final randomPart2 = random.nextInt(999999).toString().padLeft(6, '0');

      // Create device ID: username + emulatorSerial (if available) + timestamp + random
      // This ensures each login creates a unique user
      String deviceId;
      if (emulatorSerial != null &&
          emulatorSerial.isNotEmpty &&
          emulatorSerial != 'unknown') {
        // Include emulator serial for uniqueness across emulators
        deviceId =
            '${username}_${emulatorSerial}_${timestamp}_${randomPart1}_${randomPart2}';
      } else {
        // Fallback: use device base ID + timestamp + random
        deviceId =
            '${username}_${deviceBaseId}_${timestamp}_${randomPart1}_${randomPart2}';
      }

      // Ensure device ID is at least 10 bytes
      if (deviceId.length < 10) {
        deviceId = 'user-${deviceId}'.substring(0, 10);
      }

      // Truncate if too long (max 128 bytes)
      if (deviceId.length > 128) {
        deviceId = deviceId.substring(0, 128);
      }

      print('Generated device ID: $deviceId (length: ${deviceId.length})');
      if (emulatorSerial != null) {
        print('Emulator serial: $emulatorSerial');
      }

      return deviceId;
    } catch (e) {
      print('Error generating device ID: $e');
      // Fallback: use username + timestamp + random to ensure unique ID
      final random = Random();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final randomPart1 = random.nextInt(999999).toString().padLeft(6, '0');
      final randomPart2 = random.nextInt(999999).toString().padLeft(6, '0');
      final fallbackId =
          '${username}_${timestamp}_${randomPart1}_${randomPart2}';

      print('Using fallback device ID: $fallbackId');

      if (fallbackId.length < 10) {
        return 'user-${fallbackId}'.substring(0, 10);
      }
      return fallbackId.length > 128
          ? fallbackId.substring(0, 128)
          : fallbackId;
    }
  }

  /// Authenticate with Nakama (using device ID as username)
  Future<bool> authenticate(String username) async {
    try {
      // Clear any existing session first to ensure fresh authentication
      if (_session != null) {
        print('Clearing existing session before re-authentication');
        try {
          if (_socketClient != null) {
            await _socketClient!.close();
          }
        } catch (e) {
          print('Error closing socket: $e');
        }
        _socketClient = null;
        _session = null;
        _userId = null;
        _username = null;
        _users.clear();
      }

      if (_client == null) {
        await initialize();
      }

      print('Attempting to authenticate with host: $host, port: $port');
      print('Username: $username');

      // Get valid device ID (10-128 bytes) - unique for each login session
      final deviceId = await _getDeviceId(username);
      print('Using device ID: $deviceId (length: ${deviceId.length})');

      // Authenticate with device ID
      // Note: create: true will create a new user if device ID doesn't exist
      // Since we use unique device IDs, each login creates a new user
      // We don't pass username here to avoid ALREADY_EXISTS error
      // Username will be set via account update after authentication
      try {
        _session = await _client!.authenticateDevice(
          deviceId: deviceId,
          username: null, // Don't set username here to avoid conflicts
          create: true,
        );
      } catch (e) {
        // If user already exists with this device ID, try to authenticate without create
        print('First authentication attempt failed: $e');
        print('Trying to authenticate with existing device ID...');
        _session = await _client!.authenticateDevice(
          deviceId: deviceId,
          username: null,
          create: false,
        );
      }

      _userId = _session!.userId;
      _username = username;

      // Update account display name (not username to avoid conflicts)
      // Username in Nakama must be unique, but display name can be duplicated
      try {
        await _client!.updateAccount(
          session: _session!,
          displayName: username, // Use displayName instead of username
        );
        print('Display name updated successfully: $username');
      } catch (e) {
        print('Warning: Could not update display name: $e');
        // Continue anyway - user is authenticated even if display name update fails
      }

      print('Authentication successful!');
      print('  User ID: $_userId');
      print('  Username: $_username');
      print('  Device ID: $deviceId');

      // Initialize socket client after authentication
      await _initializeSocket();

      return true;
    } catch (e, stackTrace) {
      print('Authentication error: $e');
      print('Stack trace: $stackTrace');
      print('Host used: $host, Port: $port');
      return false;
    }
  }

  /// Join or create a chat channel
  Future<bool> joinChannel(String channelName) async {
    try {
      if (_socketClient == null) {
        await _initializeSocket();
      }

      // Join a chat channel
      final channel = await _socketClient!.joinChannel(
        target: channelName,
        type: ChannelType.room,
        persistence: true,
        hidden: false,
      );

      _channelId = channel.id;
      _channelName = channelName; // Store channel name

      print('Joined channel: $channelName (ID: ${channel.id})');
      print('Current user ID: $_userId');
      print('Current username: $_username');
      print('Initial presences count: ${channel.presences.length}');

      // Track users from channel presence
      if (channel.presences.isNotEmpty) {
        print('Processing initial presences:');
        for (final presence in channel.presences) {
          print('  - User: ${presence.username} (${presence.userId})');
          // Don't add current user to the list
          if (presence.userId != _userId) {
            _users[presence.userId] = presence.username;
            print('    Added to users list');
          } else {
            print('    Skipped (current user)');
          }
        }
      } else {
        print('No initial presences in channel');
      }

      // Cancel previous subscription if exists
      await _presenceSubscription?.cancel();

      // Listen to presence events
      _presenceSubscription = _socketClient!.onChannelPresence.listen((event) {
        print('Presence event received:');
        print('  Channel ID: ${event.channelId}');
        print('  Joins: ${event.joins?.length ?? 0}');
        print('  Leaves: ${event.leaves?.length ?? 0}');

        bool updated = false;

        if (event.joins != null && event.joins!.isNotEmpty) {
          print('Processing joins:');
          for (final presence in event.joins!) {
            print('  - User joined: ${presence.username} (${presence.userId})');
            // Don't add current user to the list
            if (presence.userId != _userId) {
              _users[presence.userId] = presence.username;
              updated = true;
              print('    Added to users list');
            } else {
              print('    Skipped (current user)');
            }
          }
        }
        if (event.leaves != null && event.leaves!.isNotEmpty) {
          print('Processing leaves:');
          for (final presence in event.leaves!) {
            print('  - User left: ${presence.username} (${presence.userId})');
            _users.remove(presence.userId);
            updated = true;
            print('    Removed from users list');
          }
        }

        // Notify listeners if users list changed
        if (updated) {
          print('Users list updated, notifying listeners...');
          _notifyUsersUpdated();
        } else {
          print('No changes to users list');
        }
      });

      // Notify initial users list
      print('Notifying initial users list...');
      _notifyUsersUpdated();

      return true;
    } catch (e) {
      print('Join channel error: $e');
      return false;
    }
  }

  /// Join or create a direct message channel with another user
  Future<bool> joinDirectMessage(String targetUserId) async {
    try {
      if (_socketClient == null) {
        await _initializeSocket();
      }

      // Join a direct message channel
      final channel = await _socketClient!.joinChannel(
        target: targetUserId,
        type: ChannelType.directMessage,
        persistence: true,
        hidden: false,
      );

      _channelId = channel.id;
      _channelName = null; // Direct messages don't have a name
      return true;
    } catch (e) {
      print('Join direct message error: $e');
      return false;
    }
  }

  /// Get list of users (from tracked users)
  List<Map<String, String>> getUsers() {
    return _users.entries
        .map((entry) => {
              'id': entry.key,
              'username': entry.value,
            })
        .toList();
  }

  /// Notify listeners that users list has been updated
  void _notifyUsersUpdated() {
    final usersList = getUsers();
    // Filter out current user
    final filteredUsers =
        usersList.where((user) => user['id'] != _userId).toList();
    _usersStreamController.add(filteredUsers);
    print('Users list updated: ${filteredUsers.length} users');
  }

  /// Get user info by ID
  Future<Map<String, String>?> getUserInfo(String userId) async {
    try {
      if (_client == null || _session == null) {
        return null;
      }

      final users = await _client!.getUsers(
        session: _session!,
        ids: [userId],
      );

      if (users.isNotEmpty) {
        return {
          'id': users.first.id,
          'username': users.first.username ?? 'Unknown',
        };
      }

      return null;
    } catch (e) {
      print('Get user info error: $e');
      return null;
    }
  }

  /// Send a text message to the channel
  Future<bool> sendTextMessage(String message) async {
    try {
      if (_socketClient == null || _channelId == null) {
        throw Exception('Not connected to channel');
      }

      await _socketClient!.sendMessage(
        channelId: _channelId!,
        content: {
          'message': message,
          'type': 'text',
        },
      );

      return true;
    } catch (e) {
      print('Send message error: $e');
      return false;
    }
  }

  /// Upload image to Minio via Nakama RPC and send as message
  Future<bool> sendImageMessage(File imageFile) async {
    try {
      if (_client == null ||
          _session == null ||
          _socketClient == null ||
          _channelId == null) {
        print('Send image error: Not connected to channel');
        throw Exception('Not connected to channel');
      }

      print('Reading image file: ${imageFile.path}');

      // Read image file as bytes
      final imageBytes = await imageFile.readAsBytes();
      print('Image size: ${imageBytes.length} bytes');

      // Check if image is too large
      if (imageBytes.length > 5 * 1024 * 1024) {
        // 5MB limit
        print('Image too large: ${imageBytes.length} bytes');
        throw Exception('Image too large. Maximum size is 5MB.');
      }

      // Encode to base64
      final base64Image = base64Encode(imageBytes);
      print('Base64 encoded size: ${base64Image.length} bytes');

      // Determine content type from file extension
      final extension = imageFile.path.split('.').last.toLowerCase();
      String contentType;
      switch (extension) {
        case 'jpg':
        case 'jpeg':
          contentType = 'image/jpeg';
          break;
        case 'png':
          contentType = 'image/png';
          break;
        case 'gif':
          contentType = 'image/gif';
          break;
        case 'webp':
          contentType = 'image/webp';
          break;
        default:
          contentType = 'image/jpeg';
      }

      // Prepare RPC request payload
      final rpcPayload = jsonEncode({
        'imageData': base64Image,
        'contentType': contentType,
        'fileName': imageFile.path.split('/').last,
      });

      print('Calling RPC upload_image...');

      // Call Nakama RPC to upload image to Minio
      final rpcResponse = await _client!.rpc(
        session: _session!,
        id: 'upload_image',
        payload: rpcPayload,
      );

      print('RPC response: $rpcResponse');

      // Parse response (rpcResponse is already a String)
      if (rpcResponse == null) {
        throw Exception('RPC response is null');
      }
      final responseData = jsonDecode(rpcResponse);

      if (responseData['success'] != true) {
        throw Exception(
            'Image upload failed: ${responseData['error'] ?? 'Unknown error'}');
      }

      final imageUrl = responseData['imageUrl'] as String;
      final objectKey = responseData['objectKey'] as String;

      print('Image uploaded successfully: $objectKey');
      print('Image URL: $imageUrl');

      // Send message with image URL
      try {
        await _socketClient!.sendMessage(
          channelId: _channelId!,
          content: {
            'type': 'image',
            'imageUrl': imageUrl,
            'objectKey': objectKey,
            'timestamp': DateTime.now().toIso8601String(),
          },
        );
        print('Image message sent successfully');
      } catch (messageError) {
        print('Message send error: $messageError');
        print('Message error stack trace: ${StackTrace.current}');
        rethrow;
      }

      return true;
    } catch (e, stackTrace) {
      print('Send image error: $e');
      print('Stack trace: $stackTrace');
      return false;
    }
  }

  /// Fetch channel message history from Nakama server
  /// Returns a map containing 'messages' and 'nextCursor' for pagination
  Future<Map<String, dynamic>> fetchChannelHistory({
    int limit = 100,
    bool forward = true,
    String? cursor,
  }) async {
    try {
      if (_client == null || _session == null) {
        print('Fetch history error: Not authenticated');
        throw Exception('Not authenticated');
      }

      if (_channelId == null) {
        print('Fetch history error: No channel joined');
        throw Exception('No channel joined');
      }

      print('Fetching channel history from server...');
      print('Channel ID: $_channelId');
      print('Limit: $limit');
      print('Cursor: $cursor');
      print('Forward: $forward');

      // Call Nakama API to list channel messages
      final result = await _client!.listChannelMessages(
        session: _session!,
        channelId: _channelId!,
        limit: limit,
        forward: forward,
        cursor: cursor,
      );

      print('Fetched ${result.messages?.length ?? 0} messages from server');
      print('Next cursor: ${result.nextCursor}');
      print('Prev cursor: ${result.prevCursor}');

      // Convert api.ChannelMessageList to List<api.ChannelMessage>
      final messages =
          result.messages?.map((msg) => msg as api.ChannelMessage).toList() ??
              [];

      return {
        'messages': messages,
        'nextCursor': result.nextCursor,
        'prevCursor': result.prevCursor,
        'cacheableCursor': result.cacheableCursor,
      };
    } catch (e, stackTrace) {
      print('Fetch channel history error: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Listen to chat messages
  Stream<api.ChannelMessage> listenToMessages() {
    if (_socketClient == null || _channelId == null) {
      throw Exception('Not connected to channel');
    }

    return _socketClient!.onChannelMessage;
  }

  /// Get image URL from Minio via Nakama RPC
  Future<String?> getImageUrl(String objectKey) async {
    try {
      if (_client == null || _session == null) {
        print('Get image URL error: Not authenticated');
        throw Exception('Not authenticated');
      }

      print('Getting image URL for object key: $objectKey');

      // Prepare RPC request payload
      final rpcPayload = jsonEncode({
        'objectKey': objectKey,
      });

      // Call Nakama RPC to get presigned URL
      final rpcResponse = await _client!.rpc(
        session: _session!,
        id: 'get_image_url',
        payload: rpcPayload,
      );

      print('RPC response: $rpcResponse');

      // Parse response (rpcResponse is already a String)
      if (rpcResponse == null) {
        throw Exception('RPC response is null');
      }
      final responseData = jsonDecode(rpcResponse);

      if (responseData['success'] != true) {
        throw Exception(
            'Get image URL failed: ${responseData['error'] ?? 'Unknown error'}');
      }

      final imageUrl = responseData['imageUrl'] as String;
      print('Image URL retrieved: $imageUrl');

      return imageUrl;
    } catch (e, stackTrace) {
      print('Get image URL error: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Download image from URL
  Future<Uint8List?> downloadImageFromUrl(String imageUrl) async {
    try {
      print('Downloading image from URL: $imageUrl');

      final originalUri = Uri.parse(imageUrl);
      Uri requestUri = originalUri;
      String? hostHeader;

      // Map internal container hostnames to an address reachable from the device/emulator.
      final internalHosts = {'nakama-minio', 'minio', 'localhost', '127.0.0.1'};
      if (internalHosts.contains(originalUri.host)) {
        String mappedHost = originalUri.host;

        if (!kIsWeb) {
          if (Platform.isAndroid) {
            // Android emulator forwards host machine through 10.0.2.2
            mappedHost = '10.0.2.2';
          } else if (Platform.isIOS) {
            // iOS simulator can reach host via localhost
            mappedHost = '127.0.0.1';
          } else if (Platform.isMacOS ||
              Platform.isWindows ||
              Platform.isLinux) {
            mappedHost = '127.0.0.1';
          }
        }

        requestUri = originalUri.replace(host: mappedHost);
        hostHeader = originalUri.hasPort
            ? '${originalUri.host}:${originalUri.port}'
            : originalUri.host;
        print(
            'Adjusted image URL for client: $requestUri (Host header: $hostHeader)');
      }

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);

      final request = await client.getUrl(requestUri);
      if (hostHeader != null) {
        request.headers.set(HttpHeaders.hostHeader, hostHeader);
      }

      final response = await request.close().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Image download timed out');
        },
      );

      if (response.statusCode != 200) {
        print('Failed to download image: ${response.statusCode}');
        return null;
      }

      final bytes = await consolidateHttpClientResponseBytes(response);
      print('Image downloaded successfully, size: ${bytes.length} bytes');

      return bytes;
    } catch (e, stackTrace) {
      print('Download image error: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Get stored image (deprecated - use getImageUrl and downloadImageFromUrl instead)
  @Deprecated('Use getImageUrl and downloadImageFromUrl instead')
  Future<Uint8List?> getStoredImage(String imageId) async {
    // This method is kept for backward compatibility
    // but now uses the new URL-based approach
    final imageUrl = await getImageUrl(imageId);
    if (imageUrl == null) return null;
    return downloadImageFromUrl(imageUrl);
  }

  /// Disconnect from Nakama
  Future<void> disconnect() async {
    await _messageSubscription?.cancel();
    _messageSubscription = null;
    await _presenceSubscription?.cancel();
    _presenceSubscription = null;

    if (_channelId != null && _socketClient != null) {
      try {
        await _socketClient!.leaveChannel(
          channelId: _channelId!,
        );
      } catch (e) {
        print('Leave channel error: $e');
      }
    }
    _channelId = null;
    _channelName = null;
    _socketClient = null;
    _session = null;
    _userId = null;
    _username = null;
    _users.clear();
  }

  /// Dispose resources
  void dispose() {
    _usersStreamController.close();
  }
}
