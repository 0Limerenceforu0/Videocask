import 'package:flutter/material.dart';
import '../../models/movie.dart';
import 'movie_card.dart';

/// 专区列表组件
class SectionList extends StatelessWidget {
  /// 专区标题
  final String title;

  /// 影片列表
  final List<Movie> movies;

  /// 查看更多回调
  final VoidCallback? onMoreTap;

  /// 是否水平滚动
  final bool horizontal;

  const SectionList({
    super.key,
    required this.title,
    required this.movies,
    this.onMoreTap,
    this.horizontal = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (movies.isEmpty) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题栏
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 标题
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 18,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                    ),
                  ),
                ],
              ),

              // 查看更多
              if (onMoreTap != null)
                GestureDetector(
                  onTap: onMoreTap,
                  child: Row(
                    children: [
                      Text(
                        '更多',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.hintColor,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: theme.hintColor,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // 影片列表
        if (horizontal)
          SizedBox(
            height: 250,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: movies.length,
              separatorBuilder: (context, index) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                return SizedBox(
                  width: 110,
                  child: MovieCard(movie: movies[index]),
                );
              },
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: movies.length,
            separatorBuilder: (context, index) => const SizedBox(height: 0),
            itemBuilder: (context, index) {
              return MovieCardHorizontal(movie: movies[index]);
            },
          ),

        const SizedBox(height: 16),
      ],
    );
  }
}
