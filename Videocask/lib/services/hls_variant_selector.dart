/// HLS master playlist 的清晰度选档（纯函数，可单测）。
///
/// mpv / hls.js 默认挑码率最高的一档；用户设了固定清晰度时，需要先把 master
/// 里的变体按画面高度挑出来，再交给播放器。
class HlsVariantSelector {
  const HlsVariantSelector._();

  /// 目标清晰度对应的画面高度（px）；'自动' / 未知返回 null。
  static int? targetHeightOf(String quality) {
    switch (quality) {
      case '标清':
        return 480;
      case '高清':
        return 720;
      case '1080P':
        return 1080;
      case '4K':
        return 2160;
      default:
        return null;
    }
  }

  /// 选择变体地址；没有可用变体时返回 null。
  ///
  /// - [quality] 为「自动」：沿用原行为，取最高码率的一档；
  /// - 固定档位：取「不超过目标高度」里最高的一档；若全部都高于目标
  ///   （例如只有 4K 一路），退而取最低的一档，避免直接播最高码率。
  static String? pick({
    required String content,
    required String baseUrl,
    required String quality,
  }) {
    final lines = content.split('\n');
    final variants = <_HlsVariant>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF')) continue;
      final bwMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
      final bandwidth =
          bwMatch != null ? int.tryParse(bwMatch.group(1)!) : null;
      final resMatch =
          RegExp(r'RESOLUTION=\d+x(\d+)', caseSensitive: false).firstMatch(line);
      final height = resMatch != null ? int.tryParse(resMatch.group(1)!) : null;
      var j = i + 1;
      while (j < lines.length) {
        final next = lines[j].trim();
        if (next.isEmpty || next.startsWith('#')) {
          j++;
          continue;
        }
        variants.add(
          _HlsVariant(
            url: _resolveUrl(baseUrl, next),
            bandwidth: bandwidth ?? 0,
            height: height,
          ),
        );
        break;
      }
    }
    if (variants.isEmpty) return null;

    final target = targetHeightOf(quality);
    if (target == null) {
      variants.sort((a, b) => a.bandwidth.compareTo(b.bandwidth));
      return variants.last.url;
    }

    // 缺 RESOLUTION 的变体用码率估算高度，避免整档被跳过。
    for (final v in variants) {
      v.height ??= estimateHeight(v.bandwidth ~/ 1000);
    }
    final atMost = variants.where((v) => v.height! <= target).toList()
      ..sort((a, b) => b.height!.compareTo(a.height!));
    if (atMost.isNotEmpty) return atMost.first.url;

    variants.sort((a, b) => a.height!.compareTo(b.height!));
    return variants.first.url;
  }

  /// 由带宽估算画面高度（[bandwidthKbps] 单位为 kbps）。
  static int estimateHeight(int bandwidthKbps) {
    if (bandwidthKbps <= 0) return 480;
    if (bandwidthKbps < 1200) return 480;
    if (bandwidthKbps < 3000) return 720;
    if (bandwidthKbps < 8000) return 1080;
    return 2160;
  }

  static String _resolveUrl(String baseUrl, String ref) {
    if (ref.startsWith('http://') || ref.startsWith('https://')) {
      return ref;
    }
    return Uri.parse(baseUrl).resolve(ref).toString();
  }
}

/// master playlist 里的一个码率变体。
class _HlsVariant {
  _HlsVariant({
    required this.url,
    required this.bandwidth,
    this.height,
  });

  final String url;

  /// 带宽（bps）。
  final int bandwidth;

  /// 画面高度（px）；缺 RESOLUTION 时为 null，后续用带宽估算。
  int? height;
}
