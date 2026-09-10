import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/movie.dart';
import '../../services/dlna_playback_url_resolver.dart';
import '../../services/dlna_service.dart';
import 'detail_player_side_panel.dart';

typedef DetailDlnaCastCallback = Future<bool> Function(
  DlnaDevice device,
  String castUrl,
);

/// DLNA 投屏设备选择（Android）。
enum DetailDlnaPresentation {
  /// 非全屏：紧凑底部弹层，尽量不遮挡播放器。
  compactBottomSheet,

  /// 全屏：右侧半透明竖向面板。
  sidePanel,
}

class DetailDlnaSheet {
  DetailDlnaSheet._();

  static Future<void> show({
    required BuildContext context,
    required DlnaService dlnaService,
    required DlnaPlaybackUrlResolver urlResolver,
    required Movie movie,
    required String currentPlayUrl,
    String? activeStreamUrl,
    String? episodeUrl,
    required int episodeIndex,
    required String sourceId,
    required DetailDlnaCastCallback onCast,
    DetailDlnaPresentation presentation =
        DetailDlnaPresentation.compactBottomSheet,
  }) async {
    if (!Platform.isAndroid) return;

    final l10n = AppLocalizations.of(context)!;
    final resolve = await urlResolver.resolve(
      currentPlayUrl: currentPlayUrl,
      activeStreamUrl: activeStreamUrl,
      episodeUrl: episodeUrl,
      movieId: movie.id,
      episodeIndex: episodeIndex,
      sourceId: sourceId,
    );

    if (!context.mounted) return;
    if (!resolve.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_failureMessage(l10n, resolve.failure!))),
      );
      return;
    }

    final castUrl = resolve.url!;
    final sheet = _DlnaDeviceSheet(
      l10n: l10n,
      dlnaService: dlnaService,
      movieTitle: movie.name,
      castUrl: castUrl,
      onCast: onCast,
      embeddedInSidePanel: presentation == DetailDlnaPresentation.sidePanel,
    );

    switch (presentation) {
      case DetailDlnaPresentation.sidePanel:
        await DetailPlayerSidePanel.show<void>(
          context: context,
          title: l10n.detailDlnaTitle,
          child: sheet,
        );
      case DetailDlnaPresentation.compactBottomSheet:
        final maxHeight = MediaQuery.sizeOf(context).height * 0.36;
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          constraints: BoxConstraints(maxHeight: maxHeight),
          builder: (_) => sheet,
        );
    }
  }

  static String _failureMessage(
    AppLocalizations l10n,
    DlnaResolveFailure failure,
  ) {
    switch (failure) {
      case DlnaResolveFailure.noLanIp:
        return l10n.detailDlnaNoLanIp;
      case DlnaResolveFailure.noActiveStream:
        return l10n.detailDlnaNoActiveStream;
      case DlnaResolveFailure.unsupportedScheme:
        return l10n.detailDlnaUnsupportedSource;
      case DlnaResolveFailure.localServeFailed:
        return l10n.detailDlnaLocalServeFailed;
      case DlnaResolveFailure.resolveEmpty:
        return l10n.detailDlnaResolveEmpty;
    }
  }
}

class _DlnaDeviceSheet extends StatefulWidget {
  const _DlnaDeviceSheet({
    required this.l10n,
    required this.dlnaService,
    required this.movieTitle,
    required this.castUrl,
    required this.onCast,
    this.embeddedInSidePanel = false,
  });

  final AppLocalizations l10n;
  final DlnaService dlnaService;
  final String movieTitle;
  final String castUrl;
  final DetailDlnaCastCallback onCast;
  final bool embeddedInSidePanel;

  @override
  State<_DlnaDeviceSheet> createState() => _DlnaDeviceSheetState();
}

class _DlnaDeviceSheetState extends State<_DlnaDeviceSheet> {
  bool _searching = true;
  String? _castingDeviceId;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshDevices());
  }

  Future<void> _refreshDevices() async {
    setState(() => _searching = true);
    await widget.dlnaService.searchDevices();
    if (!mounted) return;
    setState(() => _searching = false);
  }

  @override
  void dispose() {
    widget.dlnaService.stopSearch();
    super.dispose();
  }

  Future<void> _pickDevice(DlnaDevice device) async {
    setState(() => _castingDeviceId = device.uuid);
    final ok = await widget.onCast(device, widget.castUrl);
    if (!mounted) return;
    setState(() => _castingDeviceId = null);
    if (ok) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.l10n.detailDlnaCastOkNamed(device.name)),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.l10n.detailDlnaCastFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final devices = widget.dlnaService.devices;

    final deviceList = _searching
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(widget.l10n.detailDlnaSearching),
                ],
              ),
            ),
          )
        : devices.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(widget.l10n.detailDlnaEmpty),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: devices.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final d = devices[i];
                  final casting = _castingDeviceId == d.uuid;
                  return ListTile(
                    leading: const Icon(Icons.tv_rounded),
                    title: Text(d.name),
                    subtitle:
                        d.model.isNotEmpty ? Text(d.model, maxLines: 1) : null,
                    trailing: casting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: casting ? null : () => _pickDevice(d),
                  );
                },
              );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.embeddedInSidePanel) ...[
          Text(
            widget.l10n.detailDlnaTitle,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
        ],
        Text(
          widget.l10n.detailDlnaHint,
          style: TextStyle(
            fontSize: 12,
            color: widget.embeddedInSidePanel
                ? Colors.white54
                : Theme.of(context).colorScheme.onSurface.withValues(
                      alpha: 0.65,
                    ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _searching ? null : _refreshDevices,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(widget.l10n.detailDlnaRefresh),
          ),
        ),
        if (widget.embeddedInSidePanel)
          Expanded(child: deviceList)
        else
          Flexible(child: deviceList),
      ],
    );

    final padded = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: body,
    );

    if (widget.embeddedInSidePanel) return padded;
    return SafeArea(child: padded);
  }
}
