import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/pages/detail/detail_components.dart';

/// 磁力加载提示的回归测试（2026-10-28）。
///
/// 演进过程：
/// - 第一版只有一个转圈 + 「准备中…」，用户不知道卡在哪一步；
/// - 第二版改成 6 行逐条清单，用户反馈「提示每次显示一行就行了」
///   （在详情页 ~300dp 的小播放器里太占地方）。
///
/// 当前契约：
/// 1. 只显示**当前这一步**，历史步骤与后续步骤都不出现；
/// 2. 已判定「连不上任何节点」时，结论优先，步骤提示让位；
/// 3. 第 2 次自动尝试必须显式标注轮次。
void main() {
  const labels = [
    '启动 P2P 引擎',
    '解析种子元数据',
    '连接节点',
    '选定视频文件',
    '缓冲首段数据',
    '交给播放器',
  ];

  Future<void> pumpBar(
    WidgetTester tester, {
    required int stage,
    int attempt = 1,
    String attemptLabel = '',
    bool deadSwarm = false,
    String message = '正在解析磁力元数据…',
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              DetailComponents.buildTorrentProgressBar(
                3,
                message,
                torrentStage: stage,
                stageTotal: labels.length,
                stageProgressLabel: stage > 0 && stage <= labels.length
                    ? '第 $stage/${labels.length} 步 · ${labels[stage - 1]}'
                    : '',
                attempt: attempt,
                attemptLabel: attemptLabel,
                deadSwarm: deadSwarm,
                deadSwarmMessage: '这个资源连不上任何节点',
                deadSwarmHint: '换一个磁力资源，或改用在线线路播放。',
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('只显示当前这一步（不再列完整清单）', (tester) async {
    await pumpBar(tester, stage: 3);

    expect(find.text('第 3/6 步 · 连接节点'), findsOneWidget);
    // 别的步骤不得出现 —— 这是「一行提示」的核心约束。
    expect(find.text('启动 P2P 引擎'), findsNothing);
    expect(find.text('解析种子元数据'), findsNothing);
    expect(find.text('交给播放器'), findsNothing);
    // 旧的逐条打勾清单已移除。
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    expect(find.byIcon(Icons.circle_outlined), findsNothing);
  });

  testWidgets('步骤提示压过原始 message，避免两行重复文案', (tester) async {
    await pumpBar(tester, stage: 2);

    expect(find.text('第 2/6 步 · 解析种子元数据'), findsOneWidget);
    expect(find.text('正在解析磁力元数据…'), findsNothing);
  });

  testWidgets('第 2 次尝试会显式标注轮次', (tester) async {
    await pumpBar(tester, stage: 1, attempt: 2, attemptLabel: '第 2 次尝试');

    expect(find.text('第 1/6 步 · 启动 P2P 引擎'), findsOneWidget);
    expect(find.text('第 2 次尝试'), findsOneWidget);
  });

  testWidgets('未开始（stage=0）回退到原始 message', (tester) async {
    await pumpBar(tester, stage: 0);

    expect(find.text('正在解析磁力元数据…'), findsOneWidget);
    expect(find.textContaining('第 1/6 步'), findsNothing);
  });

  testWidgets('已判定连不上节点时，结论优先于步骤', (tester) async {
    await pumpBar(tester, stage: 5, deadSwarm: true);

    expect(find.text('这个资源连不上任何节点'), findsOneWidget);
    expect(find.textContaining('第 5/6 步'), findsNothing);
  });

  testWidgets('小窗（300dp 高）里不溢出', (tester) async {
    // 详情页顶部的磁力播放器只有 ~300dp 高。面板一旦超高，
    // Flutter 会画黄黑溢出条并把进度条顶出可视区。
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: 300,
              width: 360,
              child: Stack(
                children: [
                  DetailComponents.buildTorrentProgressBar(
                    3,
                    '正在缓冲数据…',
                    torrentStage: 5,
                    stageTotal: 6,
                    stageProgressLabel: '第 5/6 步 · 缓冲首段数据',
                    bufferPct: 12,
                    activePeers: 4,
                    seeds: 6,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
