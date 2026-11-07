import '../../../services/subtitle/subtitle_contract.dart';
import 'subtitle_language_policy.dart';

/// 「默认中文优先」的决策（纯函数，可单测）。
///
/// 优先级固定：内封中文 > 种子内中文 > 用户手选中文字幕 > 在线中文。
/// ① 有中文本地轨 → 只挂中文（默认，不开双语）；
/// ② 无中文本地轨、在线中文已挂载 → 只挂在线中文；
/// ③ 只有英文 → Web 必须双语 / 用户开双语时双语，否则先挂英文；
///    两种情况都要继续找在线中文（needOnlineChinese = true）；
/// ④ 一条轨都没有 → 提示并继续找在线中文。
///
/// [onlineChineseTrackId] 是「在线字幕挂载成功后」的轨 id；未挂载时传 null。
/// 这样在线匹配可以与本地轨共用同一套挑选逻辑，不需要第二套状态机。
SubtitleDecision decideSubtitleTracks({
  required List<SubtitleTrackInfo> tracks,
  int? onlineChineseTrackId,
  bool webBilingualRequired = false,
  bool userPrefersBilingual = false,
}) {
  final chinese = tracks.where(isChineseSubtitle).toList()
    ..sort((a, b) {
      final bySource = subtitleSourceRank(a.source)
          .compareTo(subtitleSourceRank(b.source));
      return bySource != 0 ? bySource : a.id.compareTo(b.id);
    });

  if (chinese.isNotEmpty) {
    return SubtitleDecision(
      mode: SubtitleDisplayMode.chineseOnly,
      primaryId: chinese.first.id,
      reason: '检测到中文字幕轨，按「中文优先」只挂中文',
    );
  }

  if (onlineChineseTrackId != null && onlineChineseTrackId > 0) {
    return SubtitleDecision(
      mode: SubtitleDisplayMode.chineseOnly,
      primaryId: onlineChineseTrackId,
      reason: '本地无中文，使用在线匹配的中文字幕',
    );
  }

  final english = tracks.where(isEnglishSubtitle).toList();
  if (english.isNotEmpty) {
    final bilingual = webBilingualRequired || userPrefersBilingual;
    return SubtitleDecision(
      mode: bilingual
          ? SubtitleDisplayMode.bilingual
          : SubtitleDisplayMode.englishOnly,
      primaryId: english.first.id,
      needOnlineChinese: true,
      reason: bilingual
          ? '本地只有英文轨，按双语要求挂英文并继续找中文'
          : '本地只有英文轨，先挂英文并继续找在线中文',
    );
  }

  return const SubtitleDecision(
    mode: SubtitleDisplayMode.none,
    needOnlineChinese: true,
    reason: '没有可用字幕轨，尝试在线匹配中文',
  );
}
