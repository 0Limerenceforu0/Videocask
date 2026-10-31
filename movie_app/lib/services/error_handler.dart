import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import '../config/app_env.dart';
import 'debug_log.dart';

/// 全局错误处理服务
class ErrorHandler {
  ErrorHandler._();
  static final ErrorHandler _instance = ErrorHandler._();
  factory ErrorHandler() => _instance;

  /// 初始化全局错误处理
  void init() {
    // 捕获Flutter框架错误
    FlutterError.onError = (FlutterErrorDetails details) {
      _handleFlutterError(details);
    };

    PlatformDispatcher.instance.onError =
        (Object error, StackTrace stackTrace) {
      _handleDartError(error, stackTrace);
      return true;
    };
  }

  /// 处理Flutter框架错误
  void _handleFlutterError(FlutterErrorDetails details) {
    if (AppEnv.isTestMode) {
      // 测试模式下直接打印错误
      FlutterError.dumpErrorToConsole(details);
      return;
    }

    // 生产模式下，记录错误并显示友好的错误提示
    _logError('Flutter Error', details.exception, details.stack);

    // 可以在这里添加错误上报逻辑
  }

  /// 处理Dart未处理异常
  void _handleDartError(Object error, StackTrace stackTrace) {
    if (AppEnv.isTestMode) {
      // 测试模式下直接打印错误
      debugPrint('Dart Error: $error');
      debugPrint('Stack Trace: $stackTrace');
      return;
    }

    // 生产模式下，记录错误并显示友好的错误提示
    _logError('Dart Error', error, stackTrace);

    // 可以在这里添加错误上报逻辑
  }

  /// 记录错误
  void _logError(String errorType, Object error, StackTrace? stackTrace) {
    final errorMessage = '$errorType: $error';
    final stackTraceMessage = stackTrace?.toString() ?? '';

    debugPrint('\n=== ERROR REPORT ===');
    debugPrint(errorMessage);
    debugPrint(stackTraceMessage);
    debugPrint('====================\n');

    // 持久化到诊断日志（测试模式不打文件，避免污染）。
    if (!AppEnv.isTestMode) {
      DebugLog.log('Crash', errorMessage, flush: true);
      if (stackTraceMessage.isNotEmpty) {
        DebugLog.log('Crash', stackTraceMessage, flush: true);
      }
    }
  }

  /// 显示错误对话框
  void showErrorDialog(BuildContext context, String message) {
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('错误'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 处理网络错误
  String handleNetworkError(dynamic error) {
    if (error is TimeoutException) {
      return '网络连接超时，请检查网络设置';
    } else if (error.toString().contains('SocketException')) {
      return '网络连接失败，请检查网络设置';
    } else if (error.toString().contains('404')) {
      return '请求的资源不存在';
    } else if (error.toString().contains('500')) {
      return '服务器内部错误';
    } else {
      return '网络请求失败，请稍后重试';
    }
  }

  /// 处理本地存储错误
  String handleStorageError(dynamic error) {
    return '存储操作失败，请检查存储空间';
  }

  /// 处理解析错误
  String handleParseError(dynamic error) {
    return '数据解析失败，请稍后重试';
  }

  /// 处理未知错误
  String handleUnknownError(dynamic error) {
    return '发生未知错误，请稍后重试';
  }
}
