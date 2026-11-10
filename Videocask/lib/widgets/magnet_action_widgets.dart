import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../pages/detail/playback/magnet_audio_language_policy.dart';
import '../pages/detail/playback/subtitle_availability_policy.dart';
import '../services/debug_log.dart';
import '../services/magnet_download_service.dart';
import '../services/subtitle_probe/movie_subtitle_hint_service.dart';
import '../services/subtitle_probe/subtitle_probe_verdict.dart';
import '../services/subtitle_probe/torrent_subtitle_probe_service_stub.dart'
    if (dart.library.io)
        '../services/subtitle_probe/torrent_subtitle_probe_service.dart';

// 字幕徽标与音轨语言徽标共用同一套 chip 外观，避免两处各写一份导致配色漂移。
EdgeInsets _infoBadgePadding(bool compact) => EdgeInsets.symmetric(
      horizontal: compact ? 6 : 8,
      vertical: compact ? 2 : 3,
    );

BoxDecoration _infoBadgeDecoration(Color fg) => BoxDecoration(
      color: fg.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: fg.withValues(alpha: 0.35)),
    );

TextStyle _infoBadgeLabelStyle(bool compact, Color fg) => TextStyle(
      color: fg,
      fontSize: compact ? 10 : 11,
      fontWeight: FontWeight.w600,
    );

/// 磁力资源卡片上的「音轨/配音是什么语言」徽标。
///
/// **纯展示、零网络、零探测**：结论只来自资源标题标记（可选种子内文件名），
/// 搜索结果一出来就能给答案，不会给字幕探测队列增加任何 BT 连接。
/// 与 [MagnetSubtitleBadge] 分工：那个答「有没有中文字幕、什么字幕」，
/// 这个答「这条片子说什么语言」；两者互不代替。
///
/// 🔴 标题没写语言时显示「语言未知」，不写「非中文」：上游磁力索引没有音轨
/// 语言字段，「不知道」不是「没有」。
class MagnetAudioLanguageBadge extends StatelessWidget {
  const MagnetAudioLanguageBadge({
    super.key,
    required this.title,
    this.fileNames = const <String>[],
    this.compact = false,
    this.muted,
    this.accent,
  });

  final String title;

  /// 种子内文件名，仅当标题完全没线索时兜底；字幕文件会被策略层跳过。
  final List<String> fileNames;
  final bool compact;
  final Color? muted;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // StatelessWidget 没有 `widget` getter（那是 State 的），直接取字段。
    final muted = this.muted ?? theme.hintColor;
    final accent = this.accent ?? theme.colorScheme.primary;
    final result = detectMagnetAudioLanguage(title, fileNames: fileNames);
    final fg = result.isKnown ? accent : muted;
    final compact = this.compact;

    return Tooltip(
      message: audioLanguageTooltip(result),
      child: Container(
        padding: _infoBadgePadding(compact),
        decoration: _infoBadgeDecoration(fg),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              result.isKnown
                  ? Icons.audiotrack_outlined
                  : Icons.help_outline,
              size: compact ? 12 : 14,
              color: fg,
            ),
            const SizedBox(width: 4),
            Text(
              audioLanguageLabel(result.language),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _infoBadgeLabelStyle(compact, fg),
            ),
          ],
        ),
      ),
    );
  }
}

/// 磁力资源卡片上的「有没有中文字幕 / 什么字幕」徽标。
///
/// 三段式判定：
/// 1. **标题关键词**（[detectMagnetSubtitle]）：零成本，能覆盖字幕组资源
///    （标题里会写「简体内封」「双语外挂」）；
/// 2. **快速探测**（列表自动，只看元数据 + 文件清单）：不下载任何视频字节，
///    直接给出外挂字幕的硬结论；
/// 3. **深度探测**（用户点徽标才触发）：读 MKV 文件头 / 外挂字幕正文，
///    把「字幕未知」升级成「内封简中」这类结论。
///
/// 🔴 为什么第 3 段必须手动：真机实测刚 add 的种子在超时窗口内下不到
/// piece 0，让列表几十条自动去读头会全部超时，还会把正在播的磁力拖卡。
/// 前两段保证「不点就自动出结论」，第 3 段只是想更准确时的可选入口。
///
/// 🔴 列表页必须 [autoProbe]：用户是**先看徽标再决定点不点进来**，让他在
/// 列表里先点一下「检测」才给答案，等于没做这个功能。
class MagnetSubtitleBadge extends StatefulWidget {
  const MagnetSubtitleBadge({
    super.key,
    required this.title,
    this.magnetUri,
    this.imdbId,
    this.autoProbe = true,
    this.probeOrder = 0,
    this.compact = false,
    this.muted,
    this.accent,
  });

  final String title;

  /// 有磁力链接才能做真实探测；为空时退化为标题判定。
  final String? magnetUri;

  /// 索引方给的 IMDb ID。用于查「这部片子有没有在线中文字幕」的影片级提示。
  final String? imdbId;

  /// 是否在挂载时自动探测。
  ///
  /// 默认开。服务层有排队配额和播放让路，不会一进页面就开几十个 BT 连接。
  final bool autoProbe;

  /// 在列表里的序号，只用于日志定位与配额排序，不参与判定。
  final int probeOrder;

  final bool compact;
  final Color? muted;
  final Color? accent;

  @override
  State<MagnetSubtitleBadge> createState() => _MagnetSubtitleBadgeState();
}

class _MagnetSubtitleBadgeState extends State<MagnetSubtitleBadge> {
  SubtitleProbeResult? _result;
  MovieSubtitleHint? _hint;
  bool _probing = false;
  bool _deepProbing = false;
  bool _started = false;
  bool _hintStarted = false;

  @override
  void initState() {
    super.initState();
    _restoreCache();
  }

  @override
  void didUpdateWidget(covariant MagnetSubtitleBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.magnetUri != widget.magnetUri ||
        oldWidget.imdbId != widget.imdbId) {
      _result = null;
      _hint = null;
      _started = false;
      _hintStarted = false;
      _probing = false;
      _restoreCache();
    }
  }

  void _restoreCache() {
    final uri = widget.magnetUri;
    if (uri == null || uri.isEmpty) return;
    final cached = TorrentSubtitleProbeService.instance.cached(uri);
    if (cached != null) {
      _result = cached;
      _maybeStartHint(cached);
      return;
    }
    if (!widget.autoProbe) return;
    // 标题已经写明字幕形态时不再探测：既省流量，也避免「标题说简中、
    // 探测说无中文」这类互相打脸的展示（标题命中的资源实测少见但存在）。
    if (hasChineseSubtitleMark(detectMagnetSubtitle(widget.title))) return;
    // 不能在 initState 里直接 setState/await，推到帧后执行。
    WidgetsBinding.instance.addPostFrameCallback((_) => _startProbe());
  }

  Future<void> _startProbe() async {
    if (_started || _probing || _deepProbing || !mounted) return;
    final uri = widget.magnetUri;
    if (uri == null || uri.isEmpty) return;

    _started = true;
    setState(() => _probing = true);
    final result = await TorrentSubtitleProbeService.instance.probe(
      uri,
      order: widget.probeOrder,
    );
    if (!mounted) return;
    setState(() {
      _result = result;
      _probing = false;
    });
    _maybeStartHint(result);
  }

  /// 用户主动点徽标：去读 MKV 内封轨 / 外挂字幕正文。
  /// 播放中服务层会拒绝，结论里会写明原因，不会假装成功。
  Future<void> _startDeep() async {
    if (_deepProbing || _probing || !mounted) return;
    final uri = widget.magnetUri;
    if (uri == null || uri.isEmpty) return;

    setState(() => _deepProbing = true);
    final result = await TorrentSubtitleProbeService.instance.probe(
      uri,
      deep: true,
      order: widget.probeOrder,
    );
    if (!mounted) return;
    setState(() {
      _result = result;
      _deepProbing = false;
      // 深挖出中文字幕后，影片级「本片可下中字」就成了噪声。
      if (result.hasChinese) _hint = null;
    });
    _maybeStartHint(result);
  }

  void _onTap() {
    DebugLog.log(
      'SubtitleProbe',
      '徽标点击 canDeep=${_result?.canDeepProbe} '
          'auto=${widget.autoProbe} order=${widget.probeOrder} '
          'verdict=${_result?.verdict.name} depth=${_result?.depth.name}',
      flush: true,
    );
    if (_result?.canDeepProbe == true) {
      _startDeep();
    } else {
      _startProbe();
    }
  }

  /// 只有「这条资源没给出中文字幕结论」时才有必要补影片级提示。
  /// 资源自带中文字幕时再挂一个「本片可下中字」纯属噪声。
  void _maybeStartHint(SubtitleProbeResult? result) {
    if (_hintStarted || !mounted) return;
    if (result == null || result.hasChinese) return;
    _hintStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final hint = await MovieSubtitleHintService.instance.lookup(
        imdbId: widget.imdbId,
        title: widget.title,
      );
      if (!mounted) return;
      setState(() => _hint = hint);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = widget.muted ?? theme.hintColor;
    final accent = widget.accent ?? theme.colorScheme.primary;

    final result = _result;
    final canProbe = (widget.magnetUri ?? '').isNotEmpty;

    // 标题关键词命中（字幕组资源）优先展示，不必浪费一次探测。
    final legacy = detectMagnetSubtitle(widget.title);
    final hasLegacyMark = hasChineseSubtitleMark(legacy);

    String label;
    Color fg;
    IconData icon;

    if (result != null && !_deepProbing) {
      label = subtitleVerdictLabel(result);
      switch (result.verdict) {
        case SubtitleProbeVerdict.chineseText:
        case SubtitleProbeVerdict.chineseImage:
          fg = accent;
          icon = Icons.subtitles_outlined;
          break;
        case SubtitleProbeVerdict.noChinese:
          fg = muted;
          icon = Icons.subtitles_off_outlined;
          break;
        case SubtitleProbeVerdict.unknown:
          fg = muted;
          icon = Icons.help_outline;
          break;
      }
    } else if (_probing || _deepProbing) {
      label = _deepProbing ? '查内封中' : '检测字幕中';
      fg = muted;
      icon = Icons.hourglass_top;
    } else if (hasLegacyMark) {
      label = subtitleAvailabilityLabel(legacy);
      fg = accent;
      icon = Icons.subtitles_outlined;
    } else if (canProbe && widget.autoProbe) {
      // 自动探测还没轮到它：不要显示「点此检测」——用户什么都没点，
      // 说「检测中」才是真实状态。
      label = '检测字幕中';
      fg = muted;
      icon = Icons.hourglass_top;
    } else if (canProbe) {
      label = '点此检测字幕';
      fg = muted;
      icon = Icons.search;
    } else {
      label = '字幕未知';
      fg = muted;
      icon = Icons.help_outline;
    }

    final compact = widget.compact;
    final child = Container(
      padding: _infoBadgePadding(compact),
      decoration: _infoBadgeDecoration(fg),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_probing || _deepProbing)
            SizedBox(
              width: compact ? 10 : 12,
              height: compact ? 10 : 12,
              child: CircularProgressIndicator(strokeWidth: 1.4, color: fg),
            )
          else
            Icon(icon, size: compact ? 12 : 14, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _infoBadgeLabelStyle(compact, fg),
          ),
        ],
      ),
    );

    final Widget mainChip;
    final canDeep = result?.canDeepProbe ?? false;
    // 🔴 快速层没能定论时，徽标必须可点：这是把「字幕未知」升级成
    // 「内封简中」的唯一入口。明确结论 / 深挖过的结论不再重复消耗流量。
    final tappable = canProbe &&
        !_probing &&
        !_deepProbing &&
        (canDeep || (!widget.autoProbe && result == null));
    if (!tappable) {
      mainChip = Tooltip(
        message: result != null ? subtitleVerdictTooltip(result) : '',
        child: child,
      );
    } else {
      mainChip = Tooltip(
        message: canDeep
            ? '点击读取 MKV 内封轨道 / 字幕正文，进一步确认'
            : (hasLegacyMark
                ? '点击可确认种子内实际字幕'
                : '点击读取种子内容，确认有没有中文字幕'),
        child: InkWell(
          onTap: _onTap,
          borderRadius: BorderRadius.circular(6),
          child: child,
        ),
      );
    }

    final hint = _hint;
    if (hint == null || !hint.hasChinese) return mainChip;

    // 🔴 影片级提示必须和资源级结论分开：措辞用「本片」，tooltip 明说
    // 「不代表这条种子自带」，避免用户把在线字幕当成种子内封。
    final hintChip = Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: muted.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: muted.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_download_outlined,
            size: compact ? 12 : 14,
            color: muted,
          ),
          const SizedBox(width: 4),
          Text(
            '本片可下中字',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: muted,
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mainChip,
        const SizedBox(width: 6),
        Tooltip(
          message: '${hint.reason}（影片级信息，不代表这条种子自带字幕）',
          child: hintChip,
        ),
      ],
    );
  }
}

/// 「点一下就真的开始下载」的按钮。
///
/// 不再只复制磁力链接：调用 [MagnetDownloadService.start] 让 App 内的
/// libtorrent 会话直接写盘，并实时显示进度；Web 端给出明确的不支持提示。
class MagnetDownloadButton extends StatelessWidget {
  const MagnetDownloadButton({
    super.key,
    required this.magnetUri,
    required this.name,
    this.foreground,
    this.borderColor,
    this.compact = false,
  });

  final String magnetUri;
  final String name;
  final Color? foreground;
  final Color? borderColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final service = MagnetDownloadService();
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final task = service.taskFor(magnetUri);
        final active = task != null && !task.finished;
        final label = task == null
            ? l10n.detailMagnetDownload
            : (task.finished
                ? '已下载'
                : '${(task.progress * 100).toStringAsFixed(0)}%');
        return OutlinedButton.icon(
          onPressed: () => _start(context, service),
          icon: Icon(
            task == null
                ? Icons.download_outlined
                : (task.finished
                    ? Icons.download_done_rounded
                    : Icons.downloading_rounded),
            size: compact ? 16 : 18,
          ),
          label: Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: foreground ?? theme.colorScheme.onSurface,
            side: BorderSide(
              color: (borderColor ?? theme.colorScheme.outline)
                  .withValues(alpha: active ? 0.9 : 0.6),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 10,
              vertical: compact ? 6 : 8,
            ),
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: const TextStyle(fontSize: 13),
          ),
        );
      },
    );
  }

  Future<void> _start(
    BuildContext context,
    MagnetDownloadService service,
  ) async {
    final result = await service.start(magnetUri: magnetUri, name: name);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
