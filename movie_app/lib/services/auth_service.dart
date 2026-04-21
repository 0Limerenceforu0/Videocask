import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../models/user_info.dart';
import 'storage_service.dart';

/// 认证服务 - 管理游客/微信/QQ登录
///
/// 支持三种登录方式：
/// 1. 游客模式（默认）：无需登录，打开APP直接使用
/// 2. 微信登录：Windows/Web端显示二维码，Android端唤起微信APP
/// 3. QQ登录：三端均支持扫码/授权登录
///
/// 注意：当前微信/QQ登录为模拟实现（生成随机OpenID），
/// 后续对接真实SDK时只需替换对应方法的实现即可。
class AuthService with ChangeNotifier {
  AuthService._();
  static final AuthService _instance = AuthService._();
  factory AuthService() => _instance;

  final StorageService _storage = StorageService();

  /// 随机数生成器
  final _random = Random();

  /// 当前用户（User模型，用于兼容现有逻辑）
  User? _currentUser;

  /// 当前用户信息（UserInfo模型，用于UI展示）
  UserInfo _userInfo = UserInfo();

  /// 当前用户
  User? get currentUser => _currentUser;

  /// 当前用户信息（用于UI展示）
  UserInfo get userInfo => _userInfo;

  /// 是否已登录
  bool get isLoggedIn => _currentUser != null;

  /// 是否为游客模式
  bool get isGuestMode => _currentUser?.isGuest ?? true;

  /// 初始化认证服务
  Future<void> init() async {
    // 尝试从本地存储加载用户
    final savedUser = _storage.getCurrentUser();
    if (savedUser != null) {
      _currentUser = savedUser.updateActiveTime();
      await _storage.saveCurrentUser(_currentUser!);
      // 同步到 UserInfo
      _userInfo = UserInfo.fromUser(_currentUser);
    } else {
      // 默认创建游客用户
      await guestLogin();
    }
    notifyListeners();
  }

  /// 游客登录
  Future<User> guestLogin() async {
    final guestUser = User.guest();
    _currentUser = guestUser;
    _userInfo = UserInfo.fromUser(guestUser);
    await _storage.saveCurrentUser(guestUser);
    debugPrint('游客登录成功: ${guestUser.id}');
    notifyListeners();
    return guestUser;
  }

  /// 生成随机二维码Token
  ///
  /// 模拟微信/QQ OAuth流程中的二维码token，
  /// 实际项目中应由服务端生成。
  String generateQrToken(String loginType) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomStr =
        List.generate(16, (_) => _random.nextInt(16).toRadixString(16)).join();
    return '${loginType}_${timestamp}_$randomStr';
  }

  /// 生成模拟OpenID
  ///
  /// 模拟微信/QQ返回的OpenID，格式为 {type}_{随机hex字符串}。
  /// 实际项目中应由服务端通过OAuth授权码换取。
  String _generateMockOpenId(String loginType) {
    final randomStr =
        List.generate(24, (_) => _random.nextInt(16).toRadixString(16)).join();
    return '${loginType}_$randomStr';
  }

  /// 模拟扫码登录等待
  ///
  /// 模拟用户扫码后服务端验证的过程。
  /// [qrToken] 二维码token
  /// [loginType] 登录类型（wechat/qq）
  /// [timeoutSeconds] 超时时间（秒），默认120秒
  ///
  /// 返回登录成功后的OpenID，超时或失败返回null。
  /// 实际项目中这里应该轮询服务端接口检查扫码状态。
  Future<String?> _simulateQrScanLogin({
    required String qrToken,
    required String loginType,
  }) async {
    // 模拟扫码延迟（2-4秒随机）
    final delaySeconds = 2 + _random.nextInt(3);
    debugPrint('[$loginType] 等待扫码中... (模拟延迟 $delaySeconds秒)');
    await Future.delayed(Duration(seconds: delaySeconds));

    // 模拟登录成功，生成随机OpenID
    final openId = _generateMockOpenId(loginType);
    debugPrint('[$loginType] 扫码登录成功，OpenID: $openId');
    return openId;
  }

  /// 微信登录
  ///
  /// Android端：唤起微信APP授权
  /// PC/Web端：展示二维码扫码
  ///
  /// [qrToken] 可选的二维码token，如果为null则自动生成
  /// 返回登录是否成功
  ///
  /// 实际项目中需要集成fluwx或flutter_wechat等插件，
  /// 这里实现完整的登录逻辑框架。
  Future<bool> wechatLogin({String? qrToken}) async {
    try {
      // 生成或使用传入的二维码token
      qrToken ??= generateQrToken('wechat');

      // 模拟微信登录流程
      // 实际项目中：
      // 1. Android: 使用 fluwx 插件唤起微信APP授权
      //    final result = await Fluwx().sendAuth(scope: 'snsapi_base', state: qrToken);
      // 2. PC/Web: 展示二维码，轮询服务端检查扫码状态
      //    final openId = await _pollWechatQrStatus(qrToken);

      // 模拟扫码登录
      final openId = await _simulateQrScanLogin(
        qrToken: qrToken,
        loginType: 'wechat',
      );

      if (openId == null) {
        debugPrint('微信登录失败：扫码超时');
        return false;
      }

      // 创建用户
      final user = User(
        id: 'wechat_$openId',
        nickname: '微信用户',
        avatar: '',
        loginType: 'wechat',
        openId: openId,
      );

      _currentUser = user;
      _userInfo = UserInfo(
        uid: openId,
        loginType: 'wechat',
        nickname: '微信用户',
        avatar: '',
      );
      await _storage.saveCurrentUser(user);
      debugPrint('微信登录成功: ${user.id}');
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('微信登录失败: $e');
      return false;
    }
  }

  /// QQ登录
  ///
  /// Android端：唤起QQ APP授权
  /// PC/Web端：展示二维码扫码
  ///
  /// [qrToken] 可选的二维码token，如果为null则自动生成
  /// 返回登录是否成功
  ///
  /// 实际项目中需要集成flutter_qq等插件。
  Future<bool> qqLogin({String? qrToken}) async {
    try {
      // 生成或使用传入的二维码token
      qrToken ??= generateQrToken('qq');

      // 模拟QQ登录流程
      // 实际项目中：
      // 1. Android: 使用 flutter_qq 插件唤起QQ APP授权
      // 2. PC/Web: 展示二维码，轮询服务端检查扫码状态

      // 模拟扫码登录
      final openId = await _simulateQrScanLogin(
        qrToken: qrToken,
        loginType: 'qq',
      );

      if (openId == null) {
        debugPrint('QQ登录失败：扫码超时');
        return false;
      }

      // 创建用户
      final user = User(
        id: 'qq_$openId',
        nickname: 'QQ用户',
        avatar: '',
        loginType: 'qq',
        openId: openId,
      );

      _currentUser = user;
      _userInfo = UserInfo(
        uid: openId,
        loginType: 'qq',
        nickname: 'QQ用户',
        avatar: '',
      );
      await _storage.saveCurrentUser(user);
      debugPrint('QQ登录成功: ${user.id}');
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('QQ登录失败: $e');
      return false;
    }
  }

  /// 退出登录
  ///
  /// 清除当前用户信息，恢复为游客模式。
  Future<void> logout() async {
    _currentUser = null;
    _userInfo = UserInfo();
    await _storage.clearCurrentUser();
    debugPrint('已退出登录');
    notifyListeners();
  }

  /// 切换账号 - 退出当前账号，进入登录页
  Future<void> switchAccount() async {
    await logout();
    // 调用方需要导航到登录页
  }

  /// 切换到游客模式
  Future<User> switchToGuest() async {
    await logout();
    return guestLogin();
  }

  /// 更新用户信息
  Future<void> updateUserInfo({
    String? nickname,
    String? avatar,
  }) async {
    if (_currentUser == null) return;
    _currentUser = _currentUser!.copyWith(
      nickname: nickname,
      avatar: avatar,
    );
    _userInfo = _userInfo.copyWith(
      nickname: nickname,
      avatar: avatar,
    );
    await _storage.saveCurrentUser(_currentUser!);
    notifyListeners();
  }

  /// 刷新最后活跃时间
  Future<void> refreshActiveTime() async {
    if (_currentUser == null) return;
    _currentUser = _currentUser!.updateActiveTime();
    await _storage.saveCurrentUser(_currentUser!);
  }

  /// 获取登录类型显示名称
  String getLoginTypeDisplayName() {
    switch (_currentUser?.loginType) {
      case 'wechat':
        return '微信登录';
      case 'qq':
        return 'QQ登录';
      case 'guest':
        return '游客模式';
      default:
        return '未知';
    }
  }

  /// 获取格式化的登录时间
  String getFormattedLoginTime() {
    final time = _userInfo.loginTime;
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  /// 获取用户显示ID（脱敏处理）
  String getDisplayUid() {
    final uid = _userInfo.uid;
    if (uid.isEmpty || _userInfo.isGuest) return '未登录';
    if (uid.length > 12) {
      return '${uid.substring(0, 6)}...${uid.substring(uid.length - 4)}';
    }
    return uid;
  }
}
