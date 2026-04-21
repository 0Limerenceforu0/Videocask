import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'package:webdav_client/webdav_client.dart';
import '../config/constants.dart';

/// WebDAV配置
class WebDavConfig {
  final String serverUrl;
  final String username;
  final String password;
  final String remotePath;
  final String presetName;

  WebDavConfig({
    required this.serverUrl,
    required this.username,
    required this.password,
    this.remotePath = '/movie_app/',
    this.presetName = '自定义',
  });

  factory WebDavConfig.fromJson(Map<String, dynamic> json) {
    return WebDavConfig(
      serverUrl: json['serverUrl']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      password: json['password']?.toString() ?? '',
      remotePath: json['remotePath']?.toString() ?? '/movie_app/',
      presetName: json['presetName']?.toString() ?? '自定义',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'serverUrl': serverUrl,
      'username': username,
      'password': password,
      'remotePath': remotePath,
      'presetName': presetName,
    };
  }

  bool get isValid =>
      serverUrl.isNotEmpty && username.isNotEmpty && password.isNotEmpty;
}

/// WebDAV同步服务
class WebDavService {
  WebDavService._();
  static final WebDavService _instance = WebDavService._();
  factory WebDavService() => _instance;

  /// 网络操作超时时间
  static const Duration _timeout = Duration(seconds: 30);

  /// WebDAV客户端（使用webdav_client包的Client类）
  Client? _client;

  /// 当前配置
  WebDavConfig? _config;

  /// 加密器
  encrypt_lib.Encrypter? _encrypter;

  /// 初始化IV
  final encrypt_lib.IV _iv =
      encrypt_lib.IV.fromLength(AppConstants.aesIvLength);

  /// 是否已连接
  bool get isConnected => _client != null;

  /// 获取当前配置
  WebDavConfig? get config => _config;

  /// 初始化加密器
  void _initEncrypter(String password) {
    // 使用密码的SHA256哈希作为密钥
    final keyBytes = Uint8List.fromList(
      password
          .padRight(AppConstants.aesKeyLength)
          .codeUnits
          .take(AppConstants.aesKeyLength)
          .toList(),
    );
    final key = encrypt_lib.Key(keyBytes);
    _encrypter = encrypt_lib.Encrypter(encrypt_lib.AES(key));
  }

  /// 加密数据
  String encrypt(String plainText) {
    if (_encrypter == null) return plainText;
    try {
      return _encrypter!.encrypt(plainText, iv: _iv).base64;
    } catch (e) {
      debugPrint('加密失败: $e');
      return plainText;
    }
  }

  /// 解密数据
  String decrypt(String encryptedText) {
    if (_encrypter == null) return encryptedText;
    try {
      return _encrypter!.decrypt64(encryptedText, iv: _iv);
    } catch (e) {
      debugPrint('解密失败: $e');
      return encryptedText;
    }
  }

  /// 连接WebDAV服务器
  Future<bool> connect(WebDavConfig config) async {
    try {
      _config = config;
      _initEncrypter(config.password);

      // 使用newClient工厂函数创建Client实例
      _client = newClient(
        config.serverUrl,
        user: config.username,
        password: config.password,
      );

      // 测试连接 - 尝试列出根目录
      await _client!.readDir('/').timeout(_timeout);
      debugPrint('WebDAV连接成功: ${config.serverUrl}');
      return true;
    } catch (e) {
      debugPrint('WebDAV连接失败: $e');
      _client = null;
      return false;
    }
  }

  /// 断开连接
  void disconnect() {
    _client = null;
    _config = null;
    _encrypter = null;
  }

  /// 确保远程目录存在
  Future<bool> _ensureRemoteDir(String path) async {
    if (_client == null) return false;
    try {
      await _client!.readDir(path);
      return true;
    } catch (e) {
      try {
        await _client!.mkdir(path);
        return true;
      } catch (e2) {
        debugPrint('创建远程目录失败: $e2');
        return false;
      }
    }
  }

  /// 上传数据
  Future<bool> upload(String remotePath, String data) async {
    if (_client == null || _config == null) return false;
    try {
      final fullPath = '${_config!.remotePath}$remotePath';
      final parentPath = fullPath.substring(0, fullPath.lastIndexOf('/'));
      await _ensureRemoteDir(parentPath);

      final encryptedData = encrypt(data);
      final bytes = Uint8List.fromList(utf8.encode(encryptedData));

      await _client!.write(fullPath, bytes).timeout(_timeout);
      debugPrint('上传成功: $fullPath');
      return true;
    } catch (e) {
      debugPrint('上传失败: $e');
      return false;
    }
  }

  /// 下载数据
  Future<String?> download(String remotePath) async {
    if (_client == null || _config == null) return null;
    try {
      final fullPath = '${_config!.remotePath}$remotePath';
      final bytes = await _client!.read(fullPath).timeout(_timeout);
      final encryptedData = utf8.decode(bytes);
      final decryptedData = decrypt(encryptedData);
      debugPrint('下载成功: $fullPath');
      return decryptedData;
    } catch (e) {
      debugPrint('下载失败: $e');
      return null;
    }
  }

  /// 删除远程文件
  Future<bool> delete(String remotePath) async {
    if (_client == null || _config == null) return false;
    try {
      final fullPath = '${_config!.remotePath}$remotePath';
      await _client!.remove(fullPath);
      debugPrint('删除成功: $fullPath');
      return true;
    } catch (e) {
      debugPrint('删除失败: $e');
      return false;
    }
  }

  /// 检查远程文件是否存在
  Future<bool> exists(String remotePath) async {
    if (_client == null || _config == null) return false;
    try {
      final fullPath = '${_config!.remotePath}$remotePath';
      await _client!.read(fullPath);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 获取远程文件列表
  Future<List<String>> listFiles(String remotePath) async {
    if (_client == null || _config == null) return [];
    try {
      final fullPath = '${_config!.remotePath}$remotePath';
      final files = await _client!.readDir(fullPath);
      return files.map((f) => f.name ?? '').toList();
    } catch (e) {
      debugPrint('列出文件失败: $e');
      return [];
    }
  }

  /// 获取最后修改时间
  Future<DateTime?> getLastModified(String remotePath) async {
    if (_client == null || _config == null) return null;
    try {
      final fullPath = '${_config!.remotePath}$remotePath';
      final files = await _client!
          .readDir(fullPath.substring(0, fullPath.lastIndexOf('/')));
      for (final f in files) {
        if (f.name != null && f.name == remotePath.split('/').last) {
          return f.mTime;
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 上传同步数据
  Future<bool> uploadSyncData(Map<String, dynamic> syncData) async {
    final jsonStr = jsonEncode(syncData);
    return upload('sync_data.json', jsonStr);
  }

  /// 下载同步数据
  Future<Map<String, dynamic>?> downloadSyncData() async {
    final jsonStr = await download('sync_data.json');
    if (jsonStr == null) return null;
    try {
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('解析同步数据失败: $e');
      return null;
    }
  }
}
