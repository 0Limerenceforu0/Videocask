/// 播放列表模型
class Playlist {
  /// 唯一ID
  final String id;

  /// 列表名称
  final String name;

  /// 影片列表
  final List<PlaylistItem> items;

  /// 创建时间
  final DateTime createdAt;

  /// 更新时间
  final DateTime updatedAt;

  Playlist({
    required this.id,
    required this.name,
    required this.items,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 从Map创建
  factory Playlist.fromMap(Map<String, dynamic> m) {
    return Playlist(
      id: m['id'] as String? ?? '',
      name: m['name'] as String? ?? '',
      items: (m['items'] as List?)
              ?.map((e) => PlaylistItem.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: m['created_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int)
          : DateTime.now(),
      updatedAt: m['updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int)
          : DateTime.now(),
    );
  }

  /// 转换为Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'items': items.map((e) => e.toMap()).toList(),
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  /// 复制并修改部分字段
  Playlist copyWith({
    String? id,
    String? name,
    List<PlaylistItem>? items,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// 播放列表中的影片项
class PlaylistItem {
  /// 影片ID
  final String movieId;

  /// 影片名称
  final String movieName;

  /// 封面URL
  final String coverUrl;

  /// 源ID
  final String sourceId;

  PlaylistItem({
    required this.movieId,
    required this.movieName,
    required this.coverUrl,
    required this.sourceId,
  });

  /// 从Map创建
  factory PlaylistItem.fromMap(Map<String, dynamic> m) {
    return PlaylistItem(
      movieId: m['movieId'] as String? ?? '',
      movieName: m['movieName'] as String? ?? '',
      coverUrl: m['coverUrl'] as String? ?? '',
      sourceId: m['sourceId'] as String? ?? '',
    );
  }

  /// 转换为Map
  Map<String, dynamic> toMap() {
    return {
      'movieId': movieId,
      'movieName': movieName,
      'coverUrl': coverUrl,
      'sourceId': sourceId,
    };
  }
}
