part of 'detail_page.dart';

// 由 detail_page.dart 拆分而来：方法体逐字搬运，
// 通过 extension on _DetailPageState 直接访问原类的私有成员。

extension _DetailPageDlnaExt on _DetailPageState {
  Widget _buildDlnaCastingChip(AppLocalizations l10n) {
    final name = _dlnaService.currentDevice?.name ?? l10n.detailDlnaTitle;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: InputChip(
        avatar: const Icon(Icons.cast_connected, size: 18, color: Colors.white),
        label: Text(
          l10n.detailDlnaCastingNamed(name),
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
        deleteIcon: const Icon(Icons.close, size: 16, color: Colors.white70),
        onDeleted: () => unawaited(_stopDlnaCast()),
        backgroundColor: detailAccentColor(context).withValues(alpha: 0.35),
        side: BorderSide.none,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Future<void> _showDlnaSheet(Movie movie) async {
    // 注意顺序：kIsWeb 必须在前面。Web 上 dart:io 的 Platform 是抛异常的桩，
    // 写成 `!Platform.isAndroid || kIsWeb` 会先求值 Platform 而直接抛
    // Unsupported operation: Platform._operatingSystem。
    if (kIsWeb || !Platform.isAndroid) return;
    final l10n = AppLocalizations.of(context)!;
    if (_playerModule.currentPlayUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.detailDlnaNeedPlayback)),
      );
      return;
    }

    String? episodeUrl;
    if (movie.playRoutes.isNotEmpty) {
      final ri = _playerModule.currentRouteIndex.clamp(
        0,
        movie.playRoutes.length - 1,
      );
      final eps = movie.playRoutes[ri].episodes;
      final ei = _playerModule.currentEpisodeIndex;
      if (ei >= 0 && ei < eps.length) {
        episodeUrl = eps[ei].url;
      }
    }

    if (_playerModule.isFullScreen && _playerModule.isPlaying) {
      await _playerModule.pause();
      if (mounted) _setState(() {});
    }
    if (!mounted) return;

    await DetailDlnaSheet.show(
      context: context,
      dlnaService: _dlnaService,
      urlResolver: _dlnaUrlResolver,
      movie: movie,
      currentPlayUrl: _playerModule.currentPlayUrl!,
      activeStreamUrl: _playerModule.activeStreamUrl ??
          _playerModule.torrentService.streamUrl,
      episodeUrl: episodeUrl,
      episodeIndex: _playerModule.currentEpisodeIndex,
      sourceId: _detailSourceId(movie),
      onCast: (device, castUrl) => _startDlnaCast(movie, device, castUrl),
      presentation: _playerModule.isFullScreen
          ? DetailDlnaPresentation.sidePanel
          : DetailDlnaPresentation.compactBottomSheet,
    );
    if (mounted) _setState(() {});
  }

  Future<bool> _startDlnaCast(
    Movie movie,
    DlnaDevice device,
    String castUrl,
  ) async {
    await _dlnaService.connectDevice(device);
    final ok = await _dlnaService.castPlay(castUrl, title: movie.name);
    if (ok) {
      await _playerModule.pause();
      if (mounted) _setState(() {});
    }
    return ok;
  }

  Future<void> _stopDlnaCast() async {
    await _dlnaService.disconnectDevice();
    if (mounted) _setState(() {});
  }

  Future<void> _syncDlnaAfterEpisodeChange(Movie movie) async {
    if (!_dlnaService.isCasting) return;
    String? episodeUrl;
    if (movie.playRoutes.isNotEmpty) {
      final ri = _playerModule.currentRouteIndex.clamp(
        0,
        movie.playRoutes.length - 1,
      );
      final eps = movie.playRoutes[ri].episodes;
      final ei = _playerModule.currentEpisodeIndex;
      if (ei >= 0 && ei < eps.length) {
        episodeUrl = eps[ei].url;
      }
    }
    final result = await _dlnaUrlResolver.resolve(
      currentPlayUrl: _playerModule.currentPlayUrl ?? '',
      activeStreamUrl: _playerModule.activeStreamUrl ??
          _playerModule.torrentService.streamUrl,
      episodeUrl: episodeUrl,
      movieId: movie.id,
      episodeIndex: _playerModule.currentEpisodeIndex,
      sourceId: _detailSourceId(movie),
    );
    if (!result.isSuccess || !mounted) return;
    await _dlnaService.castPlay(result.url!, title: movie.name);
  }
}
