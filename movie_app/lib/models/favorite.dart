/// 收藏模型
class Favorite {
  /// 唯一标识
  final String id;

  /// 影片ID
  final String movieId;

  /// 所属源ID
  final String sourceId;

  /// 影片名称
  final String movieName;

  /// 影片封面
  final String movieCover;

  /// 影片评分
  final double rating;

  /// 影片类型
  final List<String> genres;

  /// 更新状态
  final String updateStatus;

  /// 收藏时间
  final DateTime favoriteTime;

  /// 备注
  final String remark;

  /// 观看状态：'want' 想看, 'watching' 在看, 'watched' 看过, '' 未设置
  final String watchStatus;

  Favorite({
    required this.id,
    required this.movieId,
    this.sourceId = '',
    required this.movieName,
    this.movieCover = '',
    this.rating = 0.0,
    this.genres = const [],
    this.updateStatus = '',
    DateTime? favoriteTime,
    this.remark = '',
    this.watchStatus = '',
  }) : favoriteTime = favoriteTime ?? DateTime.now();

  /// 从JSON创建
  factory Favorite.fromJson(Map<String, dynamic> json) {
    return Favorite(
      id: json['id']?.toString() ?? '',
      movieId: json['movieId']?.toString() ?? '',
      sourceId: json['sourceId']?.toString() ?? '',
      movieName: json['movieName']?.toString() ?? '',
      movieCover: json['movieCover']?.toString() ?? '',
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      genres: (json['genres'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      updateStatus: json['updateStatus']?.toString() ?? '',
      favoriteTime: json['favoriteTime'] != null
          ? DateTime.tryParse(json['favoriteTime'].toString()) ?? DateTime.now()
          : DateTime.now(),
      remark: json['remark']?.toString() ?? '',
      watchStatus: json['watchStatus']?.toString() ?? '',
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'movieId': movieId,
      'sourceId': sourceId,
      'movieName': movieName,
      'movieCover': movieCover,
      'rating': rating,
      'genres': genres,
      'updateStatus': updateStatus,
      'favoriteTime': favoriteTime.toIso8601String(),
      'remark': remark,
      'watchStatus': watchStatus,
    };
  }

  /// 复制并修改部分字段
  Favorite copyWith({
    String? id,
    String? movieId,
    String? sourceId,
    String? movieName,
    String? movieCover,
    double? rating,
    List<String>? genres,
    String? updateStatus,
    DateTime? favoriteTime,
    String? remark,
    String? watchStatus,
  }) {
    return Favorite(
      id: id ?? this.id,
      movieId: movieId ?? this.movieId,
      sourceId: sourceId ?? this.sourceId,
      movieName: movieName ?? this.movieName,
      movieCover: movieCover ?? this.movieCover,
      rating: rating ?? this.rating,
      genres: genres ?? this.genres,
      updateStatus: updateStatus ?? this.updateStatus,
      favoriteTime: favoriteTime ?? this.favoriteTime,
      remark: remark ?? this.remark,
      watchStatus: watchStatus ?? this.watchStatus,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Favorite && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Favorite(movieId: $movieId, movieName: $movieName)';
}
