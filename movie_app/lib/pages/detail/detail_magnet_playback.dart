import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

import '../../l10n/app_localizations.dart';
import '../../models/movie.dart';
import '../../services/debug_log.dart';
import '../../services/torrent_player_service.dart';
import '../../utils/magnet_episode_parser.dart';

import 'detail_player.dart';
import 'detail_torrent.dart';
import 'playback/magnet_first_frame_policy.dart';
import 'playback_error_type.dart';

typedef DetailMagnetMounted = bool Function();
typedef DetailMagnetVoidCallback = void Function();

typedef DetailMagnetFilesCallback = void Function(List<TorrentFileItem> files);

/// 一轮磁力尝试的结局。
///
/// [retryable] 表示「换一轮重新打洞可能有救」——元数据没取到、节点一个没连上、
/// 起流零数据都属于这一类；而「种子里压根没有视频文件」重试多少次都一样，
/// 直接告诉用户换资源。
class MagnetAttemptResult {
  const MagnetAttemptResult._({
    required this.ok,
    required this.retryable,
    required this.message,
    this.noFrame = false,
  });

  const MagnetAttemptResult.success()
      : ok = true,
        retryable = false,
        message = '',
        noFrame = false;

  const MagnetAttemptResult.failed({
    required this.message,
    required this.retryable,
    this.noFrame = false,
  }) : ok = false;

  final bool ok;
  final bool retryable;
  final String message;

  /// 失败原因是「流交出去了，但播放器一直没出画/没时长」。
  ///
  /// 这类失败与「连不上节点」要分开计数：连不上可以无限重试，读不出画面
  /// 重试多了也没意义（见 [MagnetFirstFramePolicy.maxNoFrameStrikes]）。
  final bool noFrame;
}

/// 磁力 P2P 边下边播（从 [DetailPage] 抽离）。
class DetailMagnetPlayback {
  DetailMagnetPlayback({
    required this.player,
    required this.torrent,
    required this.isMounted,
    required this.onStateChanged,
    required this.cancelRouteFallback,
    required this.applyPlayerTuning,
    required this.startHideTimer,
    required this.startProgressPersistTimer,
    required this.scheduleSubtitleMatch,
    required this.l10n,
    this.onStreamReady,
    this.onTorrentFilesReady,
  });

  final DetailPlayer player;
  final DetailTorrent torrent;
  final DetailMagnetMounted isMounted;
  final DetailMagnetVoidCallback onStateChanged;
  final DetailMagnetVoidCallback cancelRouteFallback;
  final Future<void> Function() applyPlayerTuning;
  final DetailMagnetVoidCallback startHideTimer;
  final DetailMagnetVoidCallback startProgressPersistTimer;
  final Future<void> Function(Movie movie, String playUrl)
      scheduleSubtitleMatch;
  final AppLocalizations l10n;
  final Future<void> Function(Movie movie)? onStreamReady;
  final DetailMagnetFilesCallback? onTorrentFilesReady;

  /// 首轮失败后自动重来的等待时间。
  ///
  /// 不要设 0：立刻重来通常还是同一批 tracker 的同一个超时窗口，等于白跑；
  /// 留 1.5s 让 libtorrent 把上一轮的死连接收掉、重新挑端口打洞。
  static const Duration _retryDelay = Duration(milliseconds: 1500);

  /// 重试间隔上限。失败次数越多说明这个资源越难连，间隔逐步拉长到 10s，
  /// 避免对死种做高频无意义的 addMagnet（每次都会新建种子对象 + 打 tracker）。
  static const Duration _retryDelayMax = Duration(seconds: 10);

  /// 是否无限自动重试。
  ///
  /// 用户 2026-10-28 明确要求：磁力连不上**不要「再试一次」按钮**，直接自动重试。
  /// 所以这里不再有轮数上限 —— 只要页面还在、播放代次没被取代，就一直重试，
  /// 由 UI 用「正在自动重试（第 N 次）」把状态说清楚。
  ///
  /// 唯一的退出条件是 [MagnetAttemptResult.retryable] 为 false（种子里压根没有
  /// 视频文件，重试一万次也一样）或页面销毁 / 被新的播放取代。
  Future<void> play(
    String magnetUri,
    Movie movie, {
    int episodeIndex = 0,
    int? preferredFileIndex,
  }) async {
    if (kIsWeb || !isMounted() || magnetUri.isEmpty) return;

    cancelRouteFallback();

    final playVersion = ++torrent.magnetPlayVersion;
    final btih = RegExp(r'btih:([a-fA-F0-9]+)').firstMatch(magnetUri)?.group(1);
    DebugLog.log(
      'Magnet',
      'play 开始: btih=${btih ?? "?"}, 影片=${movie.name}, '
      'episodeIndex=$episodeIndex, preferredFile=$preferredFileIndex',
      flush: true,
    );

    // 这里**不要**走「同一个磁力就复用种子、直接换文件起新流」的快路径
    // （曾经的写法，是「第二集点不出来」的直接原因）。
    //
    // 复用种子切集，就必须先停掉上一集的流；但种子是以 streamOnly=true 添加的，
    // 原生会登记为 ephemeral，lt_stop_stream 对它会连带 lt_remove_torrent()
    // —— 一停流种子就没了，紧接着的 startStream 只会拿到 "torrent not found"。
    // 不停流则旧流泄漏：每个流都是一个独立的 HTTP server 线程 + 256MB TorrCache，
    // 且两个流会各自 prioritize_pieces() 互相覆盖，新集拉不到数据。
    //
    // 两条路都走不通，所以切集统一走完整流程：stop() 清理旧的 → 重新 addMagnet。
    // 代价是要再取一次元数据，但第二次 tracker / DHT 已有缓存，通常比重开快得多。
    var lastError = '';
    var attempt = 0;
    var retryDelay = _retryDelay;
    // 「流交出去了但读不出画面」的连续次数。只给 1 次重试机会
    // （见 [MagnetFirstFramePolicy.maxNoFrameStrikes]），否则会对着同一个
    // 解不了的封装无限重开，用户看到的依然是黑屏，只是闪烁几下。
    var noFrameStrikes = 0;

    while (true) {
      attempt++;
      if (!isMounted() || playVersion != torrent.magnetPlayVersion) return;

      if (attempt > 1) {
        // 重试窗口：让 UI 明说「正在自动重试第 N 次」，而不是继续转圈让用户
        // 以为卡死（这正是用户投诉的「一直显示加载中」）。
        player.torrentAttempt = attempt;
        player.magnetRetrying = true;
        player.torrentStage = 1;
        player.torrentMessage = l10n.detailMagnetAutoRetry('$attempt');
        onStateChanged();
        DebugLog.log(
          'Magnet',
          '第 ${attempt - 1} 次失败（$lastError），'
          '${retryDelay.inMilliseconds}ms 后开始第 $attempt 次尝试',
          flush: true,
        );
        await Future<void>.delayed(retryDelay);
        if (!isMounted() || playVersion != torrent.magnetPlayVersion) return;
        // 退避：1.5 → 3 → 6 → 10 → 10 ...
        final next = retryDelay * 2;
        retryDelay = next > _retryDelayMax ? _retryDelayMax : next;
      }

      final result = await _attempt(
        magnetUri: magnetUri,
        movie: movie,
        playVersion: playVersion,
        attempt: attempt,
        episodeIndex: episodeIndex,
        preferredFileIndex: preferredFileIndex,
      );
      // null = 被更新的一次播放取代，或页面已销毁：静默退出。
      if (result == null) return;
      if (result.ok) return;

      lastError = result.message;
      if (!result.retryable) {
        // 重试也不会有救（例如种子里没有任何视频文件）→ 停下并说清原因。
        _fail(result.message);
        return;
      }

      if (result.noFrame) {
        noFrameStrikes++;
        if (noFrameStrikes >= MagnetFirstFramePolicy.maxNoFrameStrikes) {
          // 不是「连不上」，而是「连上了但播放器读不出画面」。重开同样的流
          // 只会继续黑，明说原因让用户换资源（截图里那种 0:00 黑屏就是它）。
          _fail(result.message, noFrame: true);
          return;
        }
      } else {
        noFrameStrikes = 0;
      }
    }
  }

  /// 跑一轮完整流程；返回 null 表示本次已被取代（不要写任何状态）。
  Future<MagnetAttemptResult?> _attempt({
    required String magnetUri,
    required Movie movie,
    required int playVersion,
    required int attempt,
    required int episodeIndex,
    required int? preferredFileIndex,
  }) async {
    bool cancelled() =>
        !isMounted() || playVersion != torrent.magnetPlayVersion;

    await player.playerService.stop();
    if (cancelled()) return null;

    // 上一轮的「连不上任何节点」结论作废，否则整个新一轮都会被那条旧结论盖住。
    player.torrentService.clearDeadSwarm();

    player.lastMagnetUri = magnetUri;
    player.magnetSourcePreparing = true;
    player.torrentAttempt = attempt;
    // 第 2 轮起整轮都保持在「自动重试」状态：只在等待的那 1.5s 里亮一下
    // 等于没提示，用户看到的会一直是普通的「第 2/6 步 · 解析种子元数据」。
    player.magnetRetrying = attempt > 1;
    player.magnetWaitingFirstFrame = false;
    player.magnetNoFrameFailure = false;
    player.torrentStep = 1;
    // 阶段 1：启动 P2P 引擎
    player.torrentStage = 1;
    player.torrentMessage = l10n.detailMagnetStageInit;
    player.playbackErrorType = PlaybackErrorType.none;
    player.playerErrorMessage = '';
    onStateChanged();

    try {
      await player.torrentService.init();
      if (cancelled()) return null;
      if (!player.torrentService.isInitialized) {
        return MagnetAttemptResult.failed(
          message: l10n.detailMagnetEngineInitFailed,
          retryable: true,
        );
      }

      // 阶段 2：登记磁力、等待种子元数据
      player.torrentStage = 2;
      player.torrentStep = 1;
      player.torrentMessage = l10n.detailMagnetParsingMeta;
      onStateChanged();

      final added = await player.torrentService.addMagnet(magnetUri);
      if (cancelled()) return null;
      if (!added) {
        return MagnetAttemptResult.failed(
          message: l10n.detailMagnetAddFailed,
          retryable: true,
        );
      }

      final pickedFileIndex = await _waitForPlayableFile(
        playVersion,
        // 第 1 轮给足 100s；第 2 轮缩到 60s —— 此时 tracker/DHT 已经打过
        // 一遍，还没有元数据基本就是没节点，再等只是让用户多干等。
        maxWait: attempt == 1
            ? const Duration(seconds: 100)
            : const Duration(seconds: 60),
        episodeIndex: episodeIndex,
        preferredFileIndex: preferredFileIndex,
        torrentTitle: movie.name,
      );
      if (cancelled()) return null;
      if (pickedFileIndex == null) {
        final svc = player.torrentService;
        final msg = svc.errorMessage;
        DebugLog.log(
          'Magnet',
          '未选到可播文件: state=${svc.state}, files=${svc.files.length}, '
          'elapsed≈${svc.metaWaitSeconds}s, err=${msg.isNotEmpty ? msg : "(空)"}',
          flush: true,
        );
        // 有文件列表但挑不出视频 = 这个种子本身没有视频，重试无意义。
        final hasFiles = svc.files.isNotEmpty;
        return MagnetAttemptResult.failed(
          message: hasFiles
              ? msg.isNotEmpty
                  ? msg
                  : l10n.detailMagnetNoVideoFile
              : l10n.detailMagnetMetaTimeout,
          retryable: !hasFiles,
        );
      }

      // 阶段 4：已选定视频文件
      player.torrentStage = 4;
      player.torrentMessage = l10n.detailMagnetStagePickFile;
      onStateChanged();
      DebugLog.log(
        'Magnet',
        '选中文件: index=$pickedFileIndex, name=${_fileNameOfIndex(pickedFileIndex)}',
        flush: true,
      );

      return await _playFileIndex(
        magnetUri: magnetUri,
        movie: movie,
        playVersion: playVersion,
        fileIndex: pickedFileIndex,
        episodeIndex: episodeIndex,
      );
    } catch (e, st) {
      debugPrint('DetailMagnetPlayback.play failed: $e\n$st');
      DebugLog.log('Magnet', 'play 异常: $e', flush: true);
      if (cancelled()) return null;
      return MagnetAttemptResult.failed(message: '$e', retryable: true);
    }
  }

  Future<MagnetAttemptResult?> _playFileIndex({
    required String magnetUri,
    required Movie movie,
    required int playVersion,
    required int fileIndex,
    required int episodeIndex,
  }) async {
    // 阶段 5：起流并缓冲首段数据（这一步最久，最多等 45s）
    player.torrentStage = 5;
    player.torrentStep = 3;
    player.torrentMessage = l10n.detailMagnetBuffering;
    onStateChanged();

    final streamUrl = await player.torrentService.playFile(fileIndex);
    if (!isMounted() || playVersion != torrent.magnetPlayVersion) return null;
    if (streamUrl == null || streamUrl.isEmpty) {
      DebugLog.log(
        'Magnet',
        'playFile 失败: index=$fileIndex, '
        'err=${player.torrentService.errorMessage}',
        flush: true,
      );
      return MagnetAttemptResult.failed(
        message: l10n.detailMagnetStreamFailed,
        retryable: true,
      );
    }

    // 🔴 45s 缓冲窗口内一个字节都没下来 —— 服务层会把空流「交接」给 mpv
    // （它刻意不置 error，否则用户会被弹回详情页，见 _waitForStreamReady 复盘），
    // 表现就是黑屏 + 进度条 0%。这种「交接但零数据」必须在这里当失败处理，
    // 触发自动二次尝试，而不是把黑屏丢给用户。
    final buffered = player.torrentService.bufferPct;
    if (buffered <= 0) {
      DebugLog.log(
        'Magnet',
        '起流后零缓冲（${player.torrentService.metaWaitSeconds}s 内无数据）: '
        'activePeers=${player.torrentService.activePeers} '
        'neverConnected=${player.torrentService.handoverWithoutPeers} '
        'seeds=${player.torrentService.seeds} '
        'speed=${player.torrentService.downloadSpeed} B/s',
        flush: true,
      );
      return MagnetAttemptResult.failed(
        message: l10n.detailMagnetNoData,
        retryable: true,
      );
    }

    DebugLog.log(
      'Magnet',
      '起播: url=$streamUrl, buffer=$buffered%, '
      'attempt=${player.torrentAttempt}',
      flush: true,
    );

    // 阶段 6：交给播放器
    player.torrentStage = 6;
    player.torrentMessage = l10n.detailMagnetStageHandoff;
    onStateChanged();

    player.lastMagnetUri = magnetUri;
    player.currentPlayUrl = MagnetEpisodeParser.fileUrl(fileIndex);
    player.activeStreamUrl = streamUrl;
    // 记下当前视频文件名，字幕匹配优先用它（release 名命中率最高）。
    player.currentMagnetFileName = _fileNameOfIndex(fileIndex);
    player.currentEpisodeIndex = episodeIndex;
    player.currentRouteIndex = 0;
    player.showReplayOverlay = false;

    await player.ensureInitialized();
    if (!isMounted() || playVersion != torrent.magnetPlayVersion) return null;

    await applyPlayerTuning();
    if (!isMounted() || playVersion != torrent.magnetPlayVersion) return null;

    // 磁力本地 HTTP 流在 open 后立即 seek 易触发 mpv/libtorrent 原生崩溃；
    // 续播改由 onDurationChanged → _applyPendingResume 在时长就绪后再 seek。
    player.resetResumeConsumeForNewOpen();
    // 交接前先记下基线：上一部片可能还残留着非零时长/位置，如果不比对基线，
    // 「时长 > 0」会把「新流根本没打开」误判成「已经出画」。
    final beforePosition = player.position;
    final beforeDuration = player.duration;
    await player.playerService.play(streamUrl);
    if (!isMounted()) return null;

    // 阶段 6 后半程：等第一帧。
    //
    // 为什么必须等：mpv open 一个本地 HTTP 流不报错不代表能播。mp4 的 moov
    // 在尾部（非 faststart）时要额外拉一段文件尾，头部解码器又要等关键帧，
    // 这段时间 UI 上是 `0:00 / 0:00` + 全黑，而且**没有终点**——用户 2026-10-28
    // 截图反馈的正是这个「没有时长的黑屏，一直黑屏」。
    final frame = await _waitForFirstFrame(
      playVersion: playVersion,
      beforePosition: beforePosition,
      beforeDuration: beforeDuration,
    );
    switch (frame) {
      case MagnetFirstFrameOutcome.cancelled:
        return null; // 已被新的播放取代
      case MagnetFirstFrameOutcome.arrived:
        break;
      case MagnetFirstFrameOutcome.noData:
      case MagnetFirstFrameOutcome.unsupported:
        final svc = player.torrentService;
        DebugLog.log(
          'Magnet',
          '交接后迟迟无画面/时长（${frame.name}）: '
          'pos=${player.position.inMilliseconds}ms '
          'dur=${player.duration.inMilliseconds}ms '
          'buffer=${svc.bufferPct}% speed=${svc.downloadSpeed} B/s '
          'peers=${svc.activePeers}',
          flush: true,
        );
        return MagnetAttemptResult.failed(
          message: frame == MagnetFirstFrameOutcome.noData
              ? l10n.detailMagnetNoFrameNoData
              : l10n.detailMagnetNoFrame,
          retryable: true,
          noFrame: true,
        );
    }

    player.magnetWaitingFirstFrame = false;
    player.magnetSourcePreparing = false;
    player.magnetRetrying = false;
    player.playback.onOpenSucceeded();
    player.torrentStep = 0;
    player.torrentStage = 0;
    player.torrentMessage = '';
    onStateChanged();
    startHideTimer();
    startProgressPersistTimer();
    unawaited(onStreamReady?.call(movie));
    unawaited(
      Future<void>.delayed(const Duration(seconds: 4), () {
        if (!isMounted()) return;
        unawaited(scheduleSubtitleMatch(movie, streamUrl));
      }),
    );
    return const MagnetAttemptResult.success();
  }

  /// 等播放器出第一帧 / 解析出时长。
  ///
  /// 判定规则抽在 [MagnetFirstFramePolicy]（纯函数，可单测）；这里只负责
  /// 轮询 + 把「正在等画面」写进 UI，避免用户对着 0:00 黑屏猜。
  ///
  /// 两种等待必须区分开：
  /// * 数据彻底不动（速度 0、缓冲不涨）→ 25s 就放弃，这就是用户看到的死黑屏；
  /// * 数据一直在流只是慢 → 放到硬上限 40s，别把慢种子误杀成死种子。
  ///
  /// 放弃时还会按「等待期有没有见过数据在动」给出不同原因，
  /// 见 [MagnetFirstFrameOutcome]。
  Future<MagnetFirstFrameOutcome> _waitForFirstFrame({
    required int playVersion,
    required Duration beforePosition,
    required Duration beforeDuration,
  }) async {
    player.magnetWaitingFirstFrame = true;
    player.torrentStage = 6;
    player.torrentMessage = l10n.detailMagnetWaitingFrame;
    if (isMounted()) onStateChanged();

    final startedAt = DateTime.now();
    // 「最后一次看到数据在动」的时刻；初值 = 现在，避免刚交接就判卡死。
    var lastActivityAt = startedAt;
    var lastBufferPct = player.torrentService.bufferPct;

    while (true) {
      if (!isMounted() || playVersion != torrent.magnetPlayVersion) {
        return MagnetFirstFrameOutcome.cancelled;
      }

      // mpv 明确报错就别等了，交给外层按失败处理（会走自动重试）。
      if (player.playbackErrorType != PlaybackErrorType.none) {
        return MagnetFirstFramePolicy.classifyStall(
          stalledFor: DateTime.now().difference(lastActivityAt),
        );
      }

      if (MagnetFirstFramePolicy.frameArrived(
        beforePosition: beforePosition,
        beforeDuration: beforeDuration,
        position: player.position,
        duration: player.duration,
      )) {
        return MagnetFirstFrameOutcome.arrived;
      }

      final now = DateTime.now();
      final svc = player.torrentService;
      final bufferPct = svc.bufferPct;
      if (bufferPct > lastBufferPct || svc.downloadSpeed > 0) {
        lastActivityAt = now;
      }
      lastBufferPct = bufferPct;

      final reason = MagnetFirstFramePolicy.giveUpReason(
        elapsed: now.difference(startedAt),
        stalledFor: now.difference(lastActivityAt),
      );
      if (reason != null) return reason;

      await Future<void>.delayed(MagnetFirstFramePolicy.pollInterval);
    }
  }

  /// 取指定索引的种子内文件名（找不到时返回空串）。
  String _fileNameOfIndex(int fileIndex) {
    final files = player.torrentService.files;
    for (final f in files) {
      if (f.index == fileIndex) return f.name;
    }
    if (fileIndex >= 0 && fileIndex < files.length) {
      return files[fileIndex].name;
    }
    return '';
  }

  Future<int?> _waitForPlayableFile(
    int playVersion, {
    Duration maxWait = const Duration(seconds: 100),
    int episodeIndex = 0,
    int? preferredFileIndex,
    String? torrentTitle,
  }) async {
    const interval = Duration(milliseconds: 300);
    var elapsed = Duration.zero;

    while (elapsed < maxWait) {
      if (!isMounted() || playVersion != torrent.magnetPlayVersion) {
        return null;
      }

      final svc = player.torrentService;
      if (svc.state == TorrentPlayState.error) return null;

      final files = svc.files;
      if (files.isNotEmpty) {
        onTorrentFilesReady?.call(files);
        final pick = MagnetEpisodeParser.pickFileIndex(
          files,
          episodeIndex: episodeIndex,
          torrentTitle: torrentTitle,
          preferredFileIndex: preferredFileIndex,
        );
        if (pick != null) return pick;
      }

      // 阶段 2 解析元数据 → 阶段 3 连接节点（拿到文件列表前就是在连节点）。
      if (svc.state == TorrentPlayState.fetchingMeta) {
        player.torrentStage = 2;
        player.torrentStep = 1;
        player.torrentMessage = l10n.detailMagnetParsingMeta;
      } else {
        player.torrentStage = 3;
        player.torrentStep = 2;
        player.torrentMessage = l10n.detailMagnetConnectingPeers;
      }
      onStateChanged();

      await Future<void>.delayed(interval);
      elapsed += interval;
    }
    return null;
  }

  void _fail(String message, {bool noFrame = false}) {
    player.magnetSourcePreparing = false;
    player.magnetRetrying = false;
    player.magnetWaitingFirstFrame = false;
    player.magnetNoFrameFailure = noFrame;
    player.torrentStep = -1;
    player.torrentStage = -1;
    player.torrentMessage = message;
    player.playerErrorMessage = message;
    player.playbackErrorType = PlaybackErrorType.magnetFailed;
    DebugLog.log(
      'Magnet',
      '最终失败（已尝试 ${player.torrentAttempt} 轮，'
      'noFrame=$noFrame）: $message',
      flush: true,
    );
    if (isMounted()) onStateChanged();
  }
}
