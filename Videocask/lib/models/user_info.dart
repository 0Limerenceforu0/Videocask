/// 用户信息模型
///
/// 用于表示应用中的用户信息，支持游客、微信、QQ三种登录方式。
/// 该模型与 [User] 模型互补，[UserInfo] 更侧重于登录展示和二维码场景。
class UserInfo {
  /// 用户ID（OpenID/UnionID）
  final String uid;

  /// 登录类型：guest/wechat/qq
  final String loginType;

  /// 昵称（可选，仅展示用）
  final String nickname;

  /// 头像URL（可选）
  final String avatar;

  /// 登录时间
  final DateTime loginTime;

  /// 是否为游客
  bool get isGuest => loginType == 'guest';

  /// 是否为微信登录
  bool get isWeChat => loginType == 'wechat';

  /// 是否为QQ登录
  bool get isQQ => loginType == 'qq';

  /// 是否已登录（非游客）
  bool get isLoggedIn => !isGuest;

  /// 登录类型显示名称
  String get loginTypeDisplayName {
    switch (loginType) {
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

  UserInfo({
    this.uid = '',
    this.loginType = 'guest',
    this.nickname = '游客',
    this.avatar = '',
    DateTime? loginTime,
  }) : loginTime = loginTime ?? DateTime.now();

  /// 创建游客用户
  factory UserInfo.guest() {
    return UserInfo(
      uid: 'guest_${DateTime.now().millisecondsSinceEpoch}',
      loginType: 'guest',
      nickname: '游客',
    );
  }

  /// 从JSON创建
  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      uid: json['uid']?.toString() ?? '',
      loginType: json['loginType']?.toString() ?? 'guest',
      nickname: json['nickname']?.toString() ?? '游客',
      avatar: json['avatar']?.toString() ?? '',
      loginTime: json['loginTime'] != null
          ? DateTime.tryParse(json['loginTime'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() => {
        'uid': uid,
        'loginType': loginType,
        'nickname': nickname,
        'avatar': avatar,
        'loginTime': loginTime.toIso8601String(),
      };

  /// 复制并修改部分字段
  UserInfo copyWith({
    String? uid,
    String? loginType,
    String? nickname,
    String? avatar,
    DateTime? loginTime,
  }) {
    return UserInfo(
      uid: uid ?? this.uid,
      loginType: loginType ?? this.loginType,
      nickname: nickname ?? this.nickname,
      avatar: avatar ?? this.avatar,
      loginTime: loginTime ?? this.loginTime,
    );
  }

  /// 从 [User] 模型创建（兼容转换）
  static UserInfo fromUser(dynamic user) {
    if (user == null) return UserInfo();
    // 支持 User 模型的字段映射
    Map<String, dynamic> data = {};
    if (user is Map) {
      data = Map<String, dynamic>.from(user);
    } else {
      // 尝试通过 toJson 转换
      try {
        data = Map<String, dynamic>.from(user.toJson() as Map);
      } catch (_) {
        // 如果无法转换，使用默认值
      }
    }
    return UserInfo(
      uid: data['openId']?.toString() ?? data['id']?.toString() ?? '',
      loginType: data['loginType']?.toString() ?? 'guest',
      nickname: data['nickname']?.toString() ?? '游客',
      avatar: data['avatar']?.toString() ?? '',
      loginTime: data['loginTime'] != null
          ? DateTime.tryParse(data['loginTime'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserInfo && other.uid == uid;
  }

  @override
  int get hashCode => uid.hashCode;

  @override
  String toString() =>
      'UserInfo(uid: $uid, loginType: $loginType, nickname: $nickname)';
}
