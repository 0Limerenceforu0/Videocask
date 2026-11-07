import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'movie_grid_layout.dart';

/// 骨架屏卡片组件
///
/// 通用的骨架屏占位组件，用于在数据加载时展示闪烁的占位效果。
/// 支持自定义宽高、圆角、颜色等属性。
class ShimmerCard extends StatelessWidget {
  /// 卡片宽度
  final double width;

  /// 卡片高度
  final double height;

  /// 圆角半径
  final double borderRadius;

  /// 基础颜色（深色）
  final Color? baseColor;

  /// 高亮颜色（浅色）
  final Color? highlightColor;

  const ShimmerCard({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8.0,
    this.baseColor,
    this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = baseColor ?? (isDark ? Colors.grey[800] : Colors.grey[300]);
    final highlight =
        highlightColor ?? (isDark ? Colors.grey[700] : Colors.grey[100]);

    return Shimmer.fromColors(
      baseColor: base!,
      highlightColor: highlight!,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[800] : Colors.white,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}

/// 首页骨架屏组件
///
/// 模拟首页布局：轮播区 + 分区标题 + 卡片网格
class HomeShimmer extends StatelessWidget {
  const HomeShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.grey[800] : Colors.grey[300];
    final highlight = isDark ? Colors.grey[700] : Colors.grey[100];

    return Shimmer.fromColors(
      baseColor: base!,
      highlightColor: highlight!,
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 轮播区占位
            _buildBannerPlaceholder(isDark),
            const SizedBox(height: 16),

            // 分类导航占位
            _buildCategoryNavPlaceholder(isDark),
            const SizedBox(height: 16),

            // 分区标题 + 横向卡片占位
            _buildSectionPlaceholder(isDark, title: '最近更新'),
            const SizedBox(height: 8),

            // 分区标题 + 横向卡片占位
            _buildSectionPlaceholder(isDark, title: '热门影视'),
            const SizedBox(height: 8),

            // 分区标题 + 网格卡片占位
            _buildSectionPlaceholder(isDark, title: '高分推荐'),
            _buildGridPlaceholder(context, isDark),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  /// 轮播区占位
  Widget _buildBannerPlaceholder(bool isDark) {
    return Container(
      height: 200,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  /// 分类导航占位
  Widget _buildCategoryNavPlaceholder(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: List.generate(5, (index) {
          return Container(
            margin: const EdgeInsets.only(right: 8),
            width: 60,
            height: 32,
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[800] : Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
          );
        }),
      ),
    );
  }

  /// 分区标题占位
  Widget _buildSectionPlaceholder(bool isDark, {required String title}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Container(
            width: 80,
            height: 20,
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[800] : Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }

  /// 网格卡片占位
  Widget _buildGridPlaceholder(BuildContext context, bool isDark) {
    final grid = MovieGridLayout.metricsForContext(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: grid.sliverDelegate,
        itemCount: 6,
        itemBuilder: (context, index) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 180,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[800] : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                height: 14,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[800] : Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 详情页骨架屏组件
///
/// 模拟详情页布局：播放器区域 + 标题 + 操作按钮 + 信息区
class DetailShimmer extends StatelessWidget {
  const DetailShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.grey[800] : Colors.grey[300];
    final highlight = isDark ? Colors.grey[700] : Colors.grey[100];

    return Shimmer.fromColors(
      baseColor: base!,
      highlightColor: highlight!,
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 播放器区域占位
            Container(
              width: double.infinity,
              height: 220,
              color: isDark ? Colors.grey[800] : Colors.grey[300],
            ),
            const SizedBox(height: 16),

            // 标题占位
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 影片名称
                  Container(
                    width: 200,
                    height: 24,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[800] : Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 评分和类型信息
                  Container(
                    width: 280,
                    height: 16,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[800] : Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 操作按钮行
                  Row(
                    children: List.generate(4, (index) {
                      return Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          height: 40,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.grey[800] : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 16),

                  // 简介占位
                  Container(
                    width: double.infinity,
                    height: 16,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[800] : Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 300,
                    height: 16,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[800] : Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 250,
                    height: 16,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[800] : Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 选集标题占位
                  Container(
                    width: 80,
                    height: 20,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[800] : Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 选集网格占位
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(12, (index) {
                      return Container(
                        width: 60,
                        height: 36,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[800] : Colors.white,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
