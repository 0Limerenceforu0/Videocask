import 'channel_portal_kind.dart';

/// 频道页纵向三模块中，各模块请求 CMS `class`（类型）参数。
///
/// - `null`：沿用页顶「类型」筛选（用户选「全部」则传空串）。
/// - 非 `null`：固定类型，须与 `AppConstants.filterGenres` 中某项一致，便于苹果 CMS 识别。
abstract final class ChannelPortalModuleCatalog {
  static List<String?> fixedGenres(ChannelPortalKind kind) => switch (kind) {
        ChannelPortalKind.movies => [null, '剧情', '动作'],
        ChannelPortalKind.tv => [null, '爱情', '悬疑'],
        ChannelPortalKind.variety => [null, '喜剧', '音乐'],
        ChannelPortalKind.anime => [null, '科幻', '奇幻'],
        ChannelPortalKind.short => [null, '古装', '家庭'],
      };
}
