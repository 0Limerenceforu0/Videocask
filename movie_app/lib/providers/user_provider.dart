import 'package:flutter/material.dart';
import '../models/user.dart';
import '../models/user_info.dart';
import '../services/auth_service.dart';

/// 用户状态管理
///
/// 作为 AuthService 和 UI 之间的桥梁，提供响应式的用户状态更新。
/// 所有用户相关的状态变更都通过此 Provider 通知 UI 刷新。
class UserProvider extends ChangeNotifier {
  final AuthService _auth = AuthService();

  /// 当前用户（User模型，兼容现有逻辑）
  User? _user;

  /// 当前用户信息（UserInfo模型，用于UI展示）
  UserInfo _userInfo = UserInfo();

  /// 当前用户
  User? get user => _user;

  /// 当前用户信息
  UserInfo get userInfo => _userInfo;

  /// 是否已登录
  bool get isLoggedIn => _user != null;

  /// 是否为游客模式
  bool get isGuestMode => _user?.isGuest ?? true;

  /// 登录类型显示名称
  String get loginTypeDisplayName => _auth.getLoginTypeDisplayName();

  /// 格式化的登录时间
  String get formattedLoginTime => _auth.getFormattedLoginTime();

  /// 用户显示ID（脱敏处理）
  String get displayUid => _auth.getDisplayUid();

  /// 初始化
  Future<void> init() async {
    await _auth.init();
    _syncFromAuth();
  }

  /// 从 AuthService 同步状态
  void _syncFromAuth() {
    _user = _auth.currentUser;
    _userInfo = _auth.userInfo;
    notifyListeners();
  }

  /// 游客登录
  Future<User> guestLogin() async {
    final user = await _auth.guestLogin();
    _syncFromAuth();
    return user;
  }

  /// 生成二维码Token
  ///
  /// [loginType] 登录类型（wechat/qq）
  /// 返回用于生成二维码的token字符串
  String generateQrToken(String loginType) {
    return _auth.generateQrToken(loginType);
  }

  /// 微信登录
  ///
  /// [qrToken] 可选的二维码token
  /// 返回登录是否成功
  Future<bool> wechatLogin({String? qrToken}) async {
    final success = await _auth.wechatLogin(qrToken: qrToken);
    _syncFromAuth();
    return success;
  }

  /// QQ登录
  ///
  /// [qrToken] 可选的二维码token
  /// 返回登录是否成功
  Future<bool> qqLogin({String? qrToken}) async {
    final success = await _auth.qqLogin(qrToken: qrToken);
    _syncFromAuth();
    return success;
  }

  /// 退出登录
  ///
  /// 退出后自动切换为游客模式
  Future<void> logout() async {
    await _auth.logout();
    // 退出后自动创建游客用户
    await _auth.guestLogin();
    _syncFromAuth();
  }

  /// 切换到游客模式
  Future<void> switchToGuest() async {
    await _auth.switchToGuest();
    _syncFromAuth();
  }

  /// 更新用户信息
  Future<void> updateUserInfo({
    String? nickname,
    String? avatar,
  }) async {
    await _auth.updateUserInfo(nickname: nickname, avatar: avatar);
    _syncFromAuth();
  }

  /// 刷新活跃时间
  Future<void> refreshActiveTime() async {
    await _auth.refreshActiveTime();
    _syncFromAuth();
  }
}
