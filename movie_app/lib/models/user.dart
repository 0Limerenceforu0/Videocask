/// 用户模型
class User {
  /// 用户唯一标识
  final String id;

  /// 用户昵称
  final String nickname;

  /// 头像URL
  final String avatar;

  /// 登录类型（guest, wechat, qq）
  final String loginType;

  /// 第三方OpenID
  final String openId;

  /// 登录时间
  final DateTime loginTime;

  /// 最后活跃时间
  final DateTime lastActiveTime;

  /// 是否为游客模式
  bool get isGuest => loginType == 'guest';

  User({
    required this.id,
    this.nickname = '',
    this.avatar = '',
    this.loginType = 'guest',
    this.openId = '',
    DateTime? loginTime,
    DateTime? lastActiveTime,
  })  : loginTime = loginTime ?? DateTime.now(),
        lastActiveTime = lastActiveTime ?? DateTime.now();

  /// 创建游客用户
  factory User.guest() {
    return User(
      id: 'guest_${DateTime.now().millisecondsSinceEpoch}',
      nickname: '游客用户',
      loginType: 'guest',
    );
  }

  /// 从JSON创建
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id']?.toString() ?? '',
      nickname: json['nickname']?.toString() ?? '',
      avatar: json['avatar']?.toString() ?? '',
      loginType: json['loginType']?.toString() ?? 'guest',
      openId: json['openId']?.toString() ?? '',
      loginTime: json['loginTime'] != null
          ? DateTime.tryParse(json['loginTime'].toString()) ?? DateTime.now()
          : DateTime.now(),
      lastActiveTime: json['lastActiveTime'] != null
          ? DateTime.tryParse(json['lastActiveTime'].toString()) ??
              DateTime.now()
          : DateTime.now(),
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nickname': nickname,
      'avatar': avatar,
      'loginType': loginType,
      'openId': openId,
      'loginTime': loginTime.toIso8601String(),
      'lastActiveTime': lastActiveTime.toIso8601String(),
    };
  }

  /// 复制并修改部分字段
  User copyWith({
    String? id,
    String? nickname,
    String? avatar,
    String? loginType,
    String? openId,
    DateTime? loginTime,
    DateTime? lastActiveTime,
  }) {
    return User(
      id: id ?? this.id,
      nickname: nickname ?? this.nickname,
      avatar: avatar ?? this.avatar,
      loginType: loginType ?? this.loginType,
      openId: openId ?? this.openId,
      loginTime: loginTime ?? this.loginTime,
      lastActiveTime: lastActiveTime ?? this.lastActiveTime,
    );
  }

  /// 更新最后活跃时间
  User updateActiveTime() {
    return copyWith(lastActiveTime: DateTime.now());
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is User && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'User(id: $id, nickname: $nickname, loginType: $loginType)';
}
