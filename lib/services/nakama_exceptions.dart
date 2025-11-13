/// Base exception for Nakama service errors
class NakamaException implements Exception {
  final String message;
  final dynamic originalError;
  final StackTrace? stackTrace;

  NakamaException(
    this.message, {
    this.originalError,
    this.stackTrace,
  });

  @override
  String toString() => 'NakamaException: $message';
}

/// Thrown when not authenticated
class NotAuthenticatedException extends NakamaException {
  NotAuthenticatedException([String? message])
      : super(message ?? 'Not authenticated');
}

/// Thrown when not connected to a channel
class NotConnectedToChannelException extends NakamaException {
  NotConnectedToChannelException([String? message])
      : super(message ?? 'Not connected to channel');
}

/// Thrown when authentication fails
class AuthenticationFailedException extends NakamaException {
  AuthenticationFailedException(String message, {dynamic error, StackTrace? stackTrace})
      : super(message, originalError: error, stackTrace: stackTrace);
}

/// Thrown when image upload fails
class ImageUploadException extends NakamaException {
  ImageUploadException(String message, {dynamic error, StackTrace? stackTrace})
      : super(message, originalError: error, stackTrace: stackTrace);
}

/// Thrown when image is too large
class ImageTooLargeException extends NakamaException {
  final int size;
  final int maxSize;

  ImageTooLargeException(this.size, this.maxSize)
      : super('Image too large: $size bytes (max: $maxSize bytes)');
}

/// Thrown when image download fails
class ImageDownloadException extends NakamaException {
  ImageDownloadException(String message, {dynamic error, StackTrace? stackTrace})
      : super(message, originalError: error, stackTrace: stackTrace);
}

/// Thrown when channel operations fail
class ChannelException extends NakamaException {
  ChannelException(String message, {dynamic error, StackTrace? stackTrace})
      : super(message, originalError: error, stackTrace: stackTrace);
}

