/// Constants for Nakama service configuration
class NakamaConstants {
  // Server configuration
  static const int httpPort = 7350;
  static const int grpcPort = 7349;
  static const int wsPort = 7350;
  static const String serverKey = 'defaultkey';
  static const bool useSSL = false;

  // Image upload limits
  static const int maxImageSizeBytes = 5 * 1024 * 1024; // 5MB
  
  // Network timeouts
  static const Duration connectionTimeout = Duration(seconds: 10);
  static const Duration downloadTimeout = Duration(seconds: 30);
  
  // Device ID constraints
  static const int minDeviceIdLength = 10;
  static const int maxDeviceIdLength = 128;
  
  // Message pagination
  static const int defaultMessageLimit = 100;
  
  // Internal hostnames that need mapping
  static const Set<String> internalHosts = {
    'nakama-minio',
    'minio',
    'localhost',
    '127.0.0.1',
  };

  NakamaConstants._(); // Prevent instantiation
}

