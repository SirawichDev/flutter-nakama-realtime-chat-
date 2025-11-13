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

import 'nakama_constants.dart';
import 'nakama_exceptions.dart';
import '../utils/logger.dart';

/// Service for handling all Nakama-related operations including
/// authentication, messaging, and image handling.
class NakamaService {
  static final NakamaService _instance = NakamaService._internal();
  factory NakamaService() => _instance;
  NakamaService._internal();

  final _logger = Logger('NakamaService');

  // Nakama clients
  NakamaBaseClient? _client;
  NakamaWebsocketClient? _socketClient;
  Session? _session;

  // User info
  String? _userId;
  String? _username;

  // Channel info
  String? _channelId;

  // Subscriptions
  StreamSubscription<ChannelMessage>? _messageSubscription;
  StreamSubscription<ChannelPresenceEvent>? _presenceSubscription;

  // Track users from presence events
  final Map<String, String> _users = {}; // userId -> username

  // Stream controller for users list updates
  final _usersStreamController =
      StreamController<List<Map<String, String>>>.broadcast();

  // Getters
  Stream<List<Map<String, String>>> get usersStream =>
      _usersStreamController.stream;
  NakamaBaseClient? get client => _client;
  Session? get session => _session;
  String? get userId => _userId;
  String? get username => _username;
  String? get channelId => _channelId;

  /// Get the appropriate host based on the platform
  String get host {
    if (Platform.isAndroid) {
      return '10.0.2.2'; // Android emulator special IP for host machine
    } else if (Platform.isIOS) {
      return '127.0.0.1'; // iOS simulator can use localhost
    } else {
      return '127.0.0.1'; // Default for other platforms
    }
  }

  /// Initialize Nakama client
  Future<void> initialize() async {
    _logger.info('Initializing Nakama client with host: $host');
    _client = getNakamaClient(
      host: host,
      ssl: NakamaConstants.useSSL,
      serverKey: NakamaConstants.serverKey,
      httpPort: NakamaConstants.httpPort,
      grpcPort: NakamaConstants.grpcPort,
    );
    _logger.success('Nakama client initialized');
  }

  /// Initialize WebSocket client
  Future<void> _initializeSocket() async {
    if (_session == null) {
      throw NotAuthenticatedException();
    }

    _logger.info('Initializing WebSocket client');
    _socketClient = NakamaWebsocketClient.init(
      host: host,
      ssl: NakamaConstants.useSSL,
      port: NakamaConstants.wsPort,
      token: _session!.token,
      onError: (error) {
        _logger.error('WebSocket error', error);
      },
    );
    _logger.success('WebSocket client initialized');
  }

  /// Generate a unique device ID for authentication
  Future<String> _generateDeviceId(String username) async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      String? emulatorSerial;
      String deviceBaseId;

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        emulatorSerial = androidInfo.serialNumber;
        deviceBaseId = androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceBaseId = iosInfo.identifierForVendor ??
            'ios-device-${DateTime.now().millisecondsSinceEpoch}';
      } else {
        deviceBaseId = 'device-${DateTime.now().millisecondsSinceEpoch}';
      }

      final deviceId = _buildDeviceId(username, emulatorSerial, deviceBaseId);
      _logger
          .debug('Generated device ID: $deviceId (length: ${deviceId.length})');

      return deviceId;
    } catch (e) {
      _logger.warning('Error generating device ID, using fallback: $e');
      return _buildFallbackDeviceId(username);
    }
  }

  /// Build device ID from components
  String _buildDeviceId(
    String username,
    String? emulatorSerial,
    String deviceBaseId,
  ) {
    final random = Random();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomPart1 = random.nextInt(999999).toString().padLeft(6, '0');
    final randomPart2 = random.nextInt(999999).toString().padLeft(6, '0');

    String deviceId;
    if (emulatorSerial != null &&
        emulatorSerial.isNotEmpty &&
        emulatorSerial != 'unknown') {
      deviceId =
          '${username}_${emulatorSerial}_${timestamp}_${randomPart1}_${randomPart2}';
    } else {
      deviceId =
          '${username}_${deviceBaseId}_${timestamp}_${randomPart1}_${randomPart2}';
    }

    return _normalizeDeviceId(deviceId);
  }

  /// Build fallback device ID
  String _buildFallbackDeviceId(String username) {
    final random = Random();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomPart1 = random.nextInt(999999).toString().padLeft(6, '0');
    final randomPart2 = random.nextInt(999999).toString().padLeft(6, '0');
    final fallbackId = '${username}_${timestamp}_${randomPart1}_${randomPart2}';

    return _normalizeDeviceId(fallbackId);
  }

  /// Normalize device ID to meet length constraints
  String _normalizeDeviceId(String deviceId) {
    if (deviceId.length < NakamaConstants.minDeviceIdLength) {
      deviceId =
          'user-$deviceId'.substring(0, NakamaConstants.minDeviceIdLength);
    }
    if (deviceId.length > NakamaConstants.maxDeviceIdLength) {
      deviceId = deviceId.substring(0, NakamaConstants.maxDeviceIdLength);
    }
    return deviceId;
  }

  /// Clear existing session and connections
  Future<void> _clearSession() async {
    if (_session == null) return;

    _logger.debug('Clearing existing session');
    try {
      await _socketClient?.close();
    } catch (e) {
      _logger.warning('Error closing socket: $e');
    }

    _socketClient = null;
    _session = null;
    _userId = null;
    _username = null;
    _users.clear();
  }

  /// Authenticate with Nakama using device ID
  Future<bool> authenticate(String username) async {
    try {
      await _clearSession();

      if (_client == null) {
        await initialize();
      }

      _logger.info('Authenticating user: $username');
      final deviceId = await _generateDeviceId(username);

      // Attempt authentication
      _session = await _authenticateWithDeviceId(deviceId);
      _userId = _session!.userId;
      _username = username;

      // Update display name
      await _updateDisplayName(username);

      _logger.success('Authentication successful');
      _logger.debug('User ID: $_userId');
      _logger.debug('Username: $_username');

      // Initialize socket client after authentication
      await _initializeSocket();

      return true;
    } catch (e, stackTrace) {
      _logger.error('Authentication failed', e, stackTrace);
      throw AuthenticationFailedException(
        'Failed to authenticate user: $username',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Authenticate with device ID, with retry logic
  Future<Session> _authenticateWithDeviceId(String deviceId) async {
    try {
      return await _client!.authenticateDevice(
        deviceId: deviceId,
        username: null,
        create: true,
      );
    } catch (e) {
      _logger.debug(
          'First authentication attempt failed, retrying without create flag');
      return await _client!.authenticateDevice(
        deviceId: deviceId,
        username: null,
        create: false,
      );
    }
  }

  /// Update account display name
  Future<void> _updateDisplayName(String displayName) async {
    try {
      await _client!.updateAccount(
        session: _session!,
        displayName: displayName,
      );
      _logger.success('Display name updated: $displayName');
    } catch (e) {
      _logger.warning('Could not update display name: $e');
    }
  }

  /// Join or create a chat channel
  Future<bool> joinChannel(String channelName) async {
    try {
      if (_socketClient == null) {
        await _initializeSocket();
      }

      _logger.info('Joining channel: $channelName');

      final channel = await _socketClient!.joinChannel(
        target: channelName,
        type: ChannelType.room,
        persistence: true,
        hidden: false,
      );

      _channelId = channel.id;

      _logger.success('Joined channel: $channelName (ID: ${channel.id})');
      _logger.debug('Initial presences count: ${channel.presences.length}');

      // Track initial users
      _processInitialPresences(channel.presences);

      // Listen to presence events
      _subscribeToPresenceEvents();

      // Notify initial users list
      _notifyUsersUpdated();

      return true;
    } catch (e, stackTrace) {
      _logger.error('Failed to join channel: $channelName', e, stackTrace);
      throw ChannelException(
        'Failed to join channel: $channelName',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Process initial presences when joining a channel
  void _processInitialPresences(List<UserPresence> presences) {
    if (presences.isEmpty) {
      _logger.debug('No initial presences in channel');
      return;
    }

    _logger.debug('Processing initial presences:');
    for (final presence in presences) {
      _logger.debug('  - User: ${presence.username} (${presence.userId})');
      if (presence.userId != _userId) {
        _users[presence.userId] = presence.username;
      }
    }
  }

  /// Subscribe to presence events
  void _subscribeToPresenceEvents() {
    _presenceSubscription?.cancel();
    _presenceSubscription = _socketClient!.onChannelPresence.listen((event) {
      _logger.debug('Presence event received');
      _logger.debug('  Joins: ${event.joins?.length ?? 0}');
      _logger.debug('  Leaves: ${event.leaves?.length ?? 0}');

      bool updated = false;

      if (event.joins != null && event.joins!.isNotEmpty) {
        updated = _processJoins(event.joins!.toList()) || updated;
      }
      if (event.leaves != null && event.leaves!.isNotEmpty) {
        updated = _processLeaves(event.leaves!.toList()) || updated;
      }

      if (updated) {
        _notifyUsersUpdated();
      }
    });
  }

  /// Process user joins
  bool _processJoins(List<UserPresence> joins) {
    bool updated = false;
    for (final presence in joins) {
      _logger
          .debug('  - User joined: ${presence.username} (${presence.userId})');
      if (presence.userId != _userId) {
        _users[presence.userId] = presence.username;
        updated = true;
      }
    }
    return updated;
  }

  /// Process user leaves
  bool _processLeaves(List<UserPresence> leaves) {
    bool updated = false;
    for (final presence in leaves) {
      _logger.debug('  - User left: ${presence.username} (${presence.userId})');
      _users.remove(presence.userId);
      updated = true;
    }
    return updated;
  }

  /// Join or create a direct message channel with another user
  Future<bool> joinDirectMessage(String targetUserId) async {
    try {
      if (_socketClient == null) {
        await _initializeSocket();
      }

      _logger.info('Joining direct message with user: $targetUserId');

      final channel = await _socketClient!.joinChannel(
        target: targetUserId,
        type: ChannelType.directMessage,
        persistence: true,
        hidden: false,
      );

      _channelId = channel.id;

      _logger.success('Joined direct message channel');
      return true;
    } catch (e, stackTrace) {
      _logger.error('Failed to join direct message', e, stackTrace);
      throw ChannelException(
        'Failed to join direct message',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Get list of users (excluding current user)
  List<Map<String, String>> getUsers() {
    return _users.entries
        .where((entry) => entry.key != _userId)
        .map((entry) => {
              'id': entry.key,
              'username': entry.value,
            })
        .toList();
  }

  /// Notify listeners that users list has been updated
  void _notifyUsersUpdated() {
    final usersList = getUsers();
    _usersStreamController.add(usersList);
    _logger.debug('Users list updated: ${usersList.length} users');
  }

  /// Get user info by ID
  Future<Map<String, String>?> getUserInfo(String userId) async {
    try {
      if (_client == null || _session == null) {
        throw NotAuthenticatedException();
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
      _logger.error('Failed to get user info', e);
      return null;
    }
  }

  /// Send a text message to the channel
  Future<bool> sendTextMessage(String message) async {
    try {
      if (_socketClient == null || _channelId == null) {
        throw NotConnectedToChannelException();
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
      _logger.error('Failed to send text message', e);
      return false;
    }
  }

  /// Upload image to Minio via Nakama RPC and send as message
  Future<bool> sendImageMessage(File imageFile) async {
    try {
      _validateConnections();

      _logger.info('Sending image: ${imageFile.path}');

      // Read and validate image
      final imageBytes = await imageFile.readAsBytes();
      _validateImageSize(imageBytes.length);

      // Upload image
      final uploadResult = await _uploadImage(imageFile, imageBytes);

      // Send message
      await _sendImageMessageToChannel(
        uploadResult['imageUrl'] as String,
        uploadResult['objectKey'] as String,
      );

      _logger.success('Image message sent successfully');
      return true;
    } catch (e, stackTrace) {
      _logger.error('Failed to send image message', e, stackTrace);
      if (e is NakamaException) rethrow;
      throw ImageUploadException(
        'Failed to send image message',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Validate that all required connections are established
  void _validateConnections() {
    if (_client == null || _session == null) {
      throw NotAuthenticatedException();
    }
    if (_socketClient == null || _channelId == null) {
      throw NotConnectedToChannelException();
    }
  }

  /// Validate image size
  void _validateImageSize(int size) {
    _logger.debug('Image size: $size bytes');
    if (size > NakamaConstants.maxImageSizeBytes) {
      throw ImageTooLargeException(size, NakamaConstants.maxImageSizeBytes);
    }
  }

  /// Upload image to storage
  Future<Map<String, String>> _uploadImage(
      File imageFile, Uint8List imageBytes) async {
    final base64Image = base64Encode(imageBytes);
    final contentType = _getContentType(imageFile.path);
    final fileName = imageFile.path.split('/').last;

    final rpcPayload = jsonEncode({
      'imageData': base64Image,
      'contentType': contentType,
      'fileName': fileName,
    });

    _logger.debug('Calling RPC upload_image...');

    final rpcResponse = await _client!.rpc(
      session: _session!,
      id: 'upload_image',
      payload: rpcPayload,
    );

    return _parseUploadResponse(rpcResponse);
  }

  /// Get content type from file path
  String _getContentType(String filePath) {
    final extension = filePath.split('.').last.toLowerCase();
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  /// Parse upload response
  Map<String, String> _parseUploadResponse(String? rpcResponse) {
    if (rpcResponse == null) {
      throw ImageUploadException('RPC response is null');
    }

    final responseData = jsonDecode(rpcResponse);
    if (responseData['success'] != true) {
      throw ImageUploadException(
        'Image upload failed: ${responseData['error'] ?? 'Unknown error'}',
      );
    }

    final imageUrl = responseData['imageUrl'] as String;
    final objectKey = responseData['objectKey'] as String;

    _logger.success('Image uploaded: $objectKey');
    _logger.debug('Image URL: $imageUrl');

    return {
      'imageUrl': imageUrl,
      'objectKey': objectKey,
    };
  }

  /// Send image message to channel
  Future<void> _sendImageMessageToChannel(
      String imageUrl, String objectKey) async {
    await _socketClient!.sendMessage(
      channelId: _channelId!,
      content: {
        'type': 'image',
        'imageUrl': imageUrl,
        'objectKey': objectKey,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Fetch channel message history from Nakama server
  Future<Map<String, dynamic>> fetchChannelHistory({
    int limit = NakamaConstants.defaultMessageLimit,
    bool forward = true,
    String? cursor,
  }) async {
    try {
      if (_client == null || _session == null) {
        throw NotAuthenticatedException();
      }
      if (_channelId == null) {
        throw NotConnectedToChannelException('No channel joined');
      }

      _logger.info('Fetching channel history (limit: $limit, cursor: $cursor)');

      final result = await _client!.listChannelMessages(
        session: _session!,
        channelId: _channelId!,
        limit: limit,
        forward: forward,
        cursor: cursor,
      );

      _logger.success('Fetched ${result.messages?.length ?? 0} messages');

      return {
        'messages': result.messages ?? [],
        'nextCursor': result.nextCursor,
        'prevCursor': result.prevCursor,
        'cacheableCursor': result.cacheableCursor,
      };
    } catch (e, stackTrace) {
      _logger.error('Failed to fetch channel history', e, stackTrace);
      rethrow;
    }
  }

  /// Listen to chat messages
  Stream<api.ChannelMessage> listenToMessages() {
    if (_socketClient == null || _channelId == null) {
      throw NotConnectedToChannelException();
    }
    return _socketClient!.onChannelMessage;
  }

  /// Get image URL from storage via Nakama RPC
  Future<String?> getImageUrl(String objectKey) async {
    try {
      if (_client == null || _session == null) {
        throw NotAuthenticatedException();
      }

      _logger.debug('Getting image URL for: $objectKey');

      final rpcPayload = jsonEncode({'objectKey': objectKey});
      final rpcResponse = await _client!.rpc(
        session: _session!,
        id: 'get_image_url',
        payload: rpcPayload,
      );

      if (rpcResponse == null) {
        throw ImageDownloadException('RPC response is null');
      }

      final responseData = jsonDecode(rpcResponse);
      if (responseData['success'] != true) {
        throw ImageDownloadException(
          'Get image URL failed: ${responseData['error'] ?? 'Unknown error'}',
        );
      }

      final imageUrl = responseData['imageUrl'] as String;
      _logger.debug('Image URL retrieved: $imageUrl');

      return imageUrl;
    } catch (e, stackTrace) {
      _logger.error('Failed to get image URL', e, stackTrace);
      return null;
    }
  }

  /// Download image from URL
  Future<Uint8List?> downloadImageFromUrl(String imageUrl) async {
    try {
      _logger.debug('Downloading image from: $imageUrl');

      final requestUri = _adjustUriForPlatform(imageUrl);
      final bytes = await _performImageDownload(requestUri);

      _logger.success('Image downloaded (${bytes.length} bytes)');
      return bytes;
    } catch (e, stackTrace) {
      _logger.error('Failed to download image', e, stackTrace);
      return null;
    }
  }

  /// Adjust URI for platform-specific networking
  Uri _adjustUriForPlatform(String imageUrl) {
    final originalUri = Uri.parse(imageUrl);

    if (!NakamaConstants.internalHosts.contains(originalUri.host)) {
      return originalUri;
    }

    String mappedHost = _getMappedHost(originalUri.host);
    final requestUri = originalUri.replace(host: mappedHost);

    _logger.debug('Adjusted URL for platform: $requestUri');
    return requestUri;
  }

  /// Get mapped host for platform
  String _getMappedHost(String originalHost) {
    if (kIsWeb) return originalHost;

    if (Platform.isAndroid) {
      return '10.0.2.2'; // Android emulator
    } else if (Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isWindows ||
        Platform.isLinux) {
      return '127.0.0.1';
    }

    return originalHost;
  }

  /// Perform image download with timeout
  Future<Uint8List> _performImageDownload(Uri uri) async {
    final client = HttpClient();
    client.connectionTimeout = NakamaConstants.connectionTimeout;

    final request = await client.getUrl(uri);
    final response = await request.close().timeout(
      NakamaConstants.downloadTimeout,
      onTimeout: () {
        throw TimeoutException('Image download timed out');
      },
    );

    if (response.statusCode != 200) {
      throw ImageDownloadException(
        'Failed to download image: ${response.statusCode}',
      );
    }

    return await consolidateHttpClientResponseBytes(response);
  }

  /// Disconnect from Nakama
  Future<void> disconnect() async {
    _logger.info('Disconnecting from Nakama');

    await _messageSubscription?.cancel();
    _messageSubscription = null;
    await _presenceSubscription?.cancel();
    _presenceSubscription = null;

    if (_channelId != null && _socketClient != null) {
      try {
        await _socketClient!.leaveChannel(channelId: _channelId!);
      } catch (e) {
        _logger.warning('Error leaving channel: $e');
      }
    }

    _channelId = null;
    _socketClient = null;
    _session = null;
    _userId = null;
    _username = null;
    _users.clear();

    _logger.success('Disconnected from Nakama');
  }

  /// Dispose resources
  void dispose() {
    _usersStreamController.close();
  }
}
