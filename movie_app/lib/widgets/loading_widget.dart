import 'package:flutter/material.dart';

/// 加载组件
class LoadingWidget extends StatelessWidget {
  /// 加载提示文字
  final String? message;

  /// 加载类型
  final LoadingType type;

  /// 尺寸
  final double size;

  const LoadingWidget({
    super.key,
    this.message,
    this.type = LoadingType.circular,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildIndicator(theme),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.hintColor,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildIndicator(ThemeData theme) {
    switch (type) {
      case LoadingType.circular:
        return SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(
              theme.colorScheme.primary,
            ),
          ),
        );
      case LoadingType.dots:
        return _DotsIndicator(
          color: theme.colorScheme.primary,
          size: size,
        );
      case LoadingType.shimmer:
        return SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
          ),
        );
    }
  }
}

/// 加载类型
enum LoadingType {
  circular,
  dots,
  shimmer,
}

/// 点状加载指示器
class _DotsIndicator extends StatefulWidget {
  final Color color;
  final double size;

  const _DotsIndicator({
    required this.color,
    required this.size,
  });

  @override
  State<_DotsIndicator> createState() => _DotsIndicatorState();
}

class _DotsIndicatorState extends State<_DotsIndicator>
    with TickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final offset = (index * 0.3 + _controller.value) % 1.0;
            final scale = 0.5 + 0.5 * (1 - (offset * 2 - 1).abs());
            final opacity = 0.3 + 0.7 * scale;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: widget.size * 0.2 * scale,
              height: widget.size * 0.2 * scale,
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: opacity),
                shape: BoxShape.circle,
              ),
            );
          },
        );
      }),
    );
  }
}

/// 全屏加载遮罩
class LoadingOverlay extends StatelessWidget {
  final bool isLoading;
  final Widget child;
  final String? message;

  const LoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: const Center(
                child: LoadingWidget(),
              ),
            ),
          ),
      ],
    );
  }
}
