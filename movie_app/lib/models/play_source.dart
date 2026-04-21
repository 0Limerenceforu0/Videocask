/// 播放源模型
class PlaySource {
  /// 源唯一标识
  final String id;

  /// 源名称
  final String name;

  /// 源地址
  final String url;

  /// 源类型（json, xml, html）
  final String type;

  /// 是否启用
  final bool enabled;

  /// 排序权重
  final int sortOrder;

  /// 是否有效（检测结果）
  final bool isValid;

  /// 最后检测时间
  final DateTime lastCheckTime;

  /// 响应时间（毫秒）
  final int responseTime;

  /// 备注说明
  final String remark;

  /// 创建时间
  final DateTime createdAt;

  PlaySource({
    required this.id,
    required this.name,
    required this.url,
    this.type = 'json',
    this.enabled = true,
    this.sortOrder = 0,
    this.isValid = true,
    DateTime? lastCheckTime,
    this.responseTime = 0,
    this.remark = '',
    DateTime? createdAt,
  })  : lastCheckTime = lastCheckTime ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  /// 从JSON创建
  factory PlaySource.fromJson(Map<String, dynamic> json) {
    return PlaySource(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      type: json['type']?.toString() ?? 'json',
      enabled: json['enabled'] as bool? ?? true,
      sortOrder: json['sortOrder'] as int? ?? 0,
      isValid: json['isValid'] as bool? ?? true,
      lastCheckTime: json['lastCheckTime'] != null
          ? DateTime.tryParse(json['lastCheckTime'].toString()) ??
              DateTime.now()
          : DateTime.now(),
      responseTime: json['responseTime'] as int? ?? 0,
      remark: json['remark']?.toString() ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'type': type,
      'enabled': enabled,
      'sortOrder': sortOrder,
      'isValid': isValid,
      'lastCheckTime': lastCheckTime.toIso8601String(),
      'responseTime': responseTime,
      'remark': remark,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// 复制并修改部分字段
  PlaySource copyWith({
    String? id,
    String? name,
    String? url,
    String? type,
    bool? enabled,
    int? sortOrder,
    bool? isValid,
    DateTime? lastCheckTime,
    int? responseTime,
    String? remark,
  }) {
    return PlaySource(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      type: type ?? this.type,
      enabled: enabled ?? this.enabled,
      sortOrder: sortOrder ?? this.sortOrder,
      isValid: isValid ?? this.isValid,
      lastCheckTime: lastCheckTime ?? this.lastCheckTime,
      responseTime: responseTime ?? this.responseTime,
      remark: remark ?? this.remark,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlaySource && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'PlaySource(id: $id, name: $name, url: $url)';
}
