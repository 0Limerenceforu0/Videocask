// ignore_for_file: prefer_const_constructors

/// 统一的 ASR 段（Whisper 兼容）
class SubtitleAiSegment {
  final double startSec;
  final double endSec;
  final String text;

  const SubtitleAiSegment({
    required this.startSec,
    required this.endSec,
    required this.text,
  });
}

/// SRT 格式化器（segment[] → SRT 文本）
class SrtFormatter {
  static String fromSegments(
    List<SubtitleAiSegment> segments, {
    String fallbackPlain = '',
  }) {
    final filtered =
        segments.where((s) => s.text.trim().isNotEmpty).toList(growable: false);
    if (filtered.isEmpty) {
      if (fallbackPlain.trim().isEmpty) return '';
      // 没时间戳时把整段纯文本作为单条字幕
      return '1\n00:00:00,000 --> 00:00:03,000\n${fallbackPlain.trim()}\n';
    }
    final buf = StringBuffer();
    for (var i = 0; i < filtered.length; i++) {
      final seg = filtered[i];
      buf.writeln((i + 1).toString());
      buf.writeln(
        '${_formatSrtTime(seg.startSec)} --> ${_formatSrtTime(seg.endSec)}',
      );
      buf.writeln(seg.text.trim());
      buf.writeln();
    }
    return buf.toString();
  }

  static String _formatSrtTime(double seconds) {
    if (seconds.isNaN || seconds.isInfinite || seconds < 0) seconds = 0.0;
    final totalMs = (seconds * 1000).round();
    final h = totalMs ~/ 3600000;
    final m = (totalMs % 3600000) ~/ 60000;
    final s = (totalMs % 60000) ~/ 1000;
    final ms = totalMs % 1000;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')},${ms.toString().padLeft(3, '0')}';
  }
}
