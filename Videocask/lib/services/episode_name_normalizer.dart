/// 历史集名归一化（仅用于展示）。
///
/// 不同片源对同一集会写成「第1集」「第01集」「第 001 集」，导致历史里
/// 看着像两条不同记录。去重仍按历史 id，这里只把展示文案对齐。
String normalizeEpisodeName(String raw) {
  final name = raw.trim();
  if (name.isEmpty) return name;
  return name.replaceAllMapped(
    RegExp(r'第\s*0*(\d+)\s*集'),
    (m) => '第${m.group(1)}集',
  );
}
