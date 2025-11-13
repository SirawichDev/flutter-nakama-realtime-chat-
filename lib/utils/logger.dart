import 'package:flutter/foundation.dart';

/// Simple logger utility for consistent logging across the app
class Logger {
  final String _name;

  Logger(this._name);

  /// Log debug message
  void debug(String message) {
    if (kDebugMode) {
      print('🔵 [$_name] $message');
    }
  }

  /// Log info message
  void info(String message) {
    if (kDebugMode) {
      print('ℹ️ [$_name] $message');
    }
  }

  /// Log warning message
  void warning(String message) {
    if (kDebugMode) {
      print('⚠️ [$_name] $message');
    }
  }

  /// Log error message
  void error(String message, [dynamic error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      print('❌ [$_name] $message');
      if (error != null) {
        print('   Error: $error');
      }
      if (stackTrace != null) {
        print('   Stack trace: $stackTrace');
      }
    }
  }

  /// Log success message
  void success(String message) {
    if (kDebugMode) {
      print('✅ [$_name] $message');
    }
  }
}
