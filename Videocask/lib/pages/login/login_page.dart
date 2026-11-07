import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../providers/user_provider.dart';

/// 登录方式枚举
enum _LoginMethod {
  wechat,
  qq,
}

/// 登录方式扩展，获取显示名称
extension _LoginMethodExtension on _LoginMethod {
  String get displayName {
    switch (this) {
      case _LoginMethod.wechat:
        return '微信';
      case _LoginMethod.qq:
        return 'QQ';
    }
  }

  String get qrHint {
    switch (this) {
      case _LoginMethod.wechat:
        return '请使用微信扫描二维码登录';
      case _LoginMethod.qq:
        return '请使用QQ扫描二维码登录';
    }
  }

  Color get brandColor {
    switch (this) {
      case _LoginMethod.wechat:
        return const Color(0xFF07C160);
      case _LoginMethod.qq:
        return const Color(0xFF12B7F5);
    }
  }

  IconData get brandIcon {
    switch (this) {
      case _LoginMethod.wechat:
        return Icons.wechat_outlined;
      case _LoginMethod.qq:
        return Icons.chat_bubble_outline;
    }
  }
}

/// 登录页面
///
/// 支持三种登录方式：
/// 1. 游客模式：无需登录，直接进入
/// 2. 微信登录：显示二维码扫码登录（模拟）
/// 3. QQ登录：显示二维码扫码登录（模拟）
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  /// 当前选中的登录方式
  _LoginMethod _currentMethod = _LoginMethod.wechat;

  /// 当前二维码Token
  String _qrToken = '';

  /// 二维码是否已过期
  bool _isQrExpired = false;

  /// 是否正在登录中
  bool _isLoggingIn = false;

  /// 二维码刷新计时器
  int _refreshCountdown = 120;

  /// 动画控制器（二维码切换动画）
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _generateQrCode();
    });
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  /// 生成新的二维码
  void _generateQrCode() {
    final userProvider = context.read<UserProvider>();
    final loginType = _currentMethod == _LoginMethod.wechat ? 'wechat' : 'qq';
    setState(() {
      _qrToken = userProvider.generateQrToken(loginType);
      _isQrExpired = false;
      _refreshCountdown = 120;
    });
    // 模拟120秒后二维码过期
    _startCountdown();
  }

  /// 开始倒计时
  void _startCountdown() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() {
        _refreshCountdown--;
      });
      if (_refreshCountdown <= 0) {
        if (mounted) {
          setState(() {
            _isQrExpired = true;
          });
        }
        return false;
      }
      return mounted && !_isLoggingIn;
    });
  }

  /// 切换登录方式
  void _switchMethod(_LoginMethod method) {
    if (method == _currentMethod || _isLoggingIn) return;
    _animationController.reverse().then((_) {
      setState(() {
        _currentMethod = method;
      });
      _generateQrCode();
      _animationController.forward();
    });
  }

  /// 执行扫码登录
  Future<void> _performQrLogin() async {
    if (_isLoggingIn) return;

    setState(() {
      _isLoggingIn = true;
    });

    final userProvider = context.read<UserProvider>();
    bool success = false;

    if (_currentMethod == _LoginMethod.wechat) {
      success = await userProvider.wechatLogin(qrToken: _qrToken);
    } else {
      success = await userProvider.qqLogin(qrToken: _qrToken);
    }

    if (mounted) {
      setState(() {
        _isLoggingIn = false;
      });

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_currentMethod.displayName}登录成功'),
            backgroundColor: _currentMethod.brandColor,
          ),
        );
        context.pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('登录失败，请重试'),
            backgroundColor: Colors.red,
          ),
        );
        // 登录失败后刷新二维码
        _generateQrCode();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final userProvider = context.watch<UserProvider>();

    final bgColor = isDark ? const Color(0xFF17181A) : const Color(0xFFF4F4F4);
    final cardColor = isDark ? const Color(0xFF222325) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('账号登录'),
        centerTitle: true,
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ===== APP Logo 和名称 =====
                _buildAppHeader(theme),

                const SizedBox(height: 28),

                // ===== 二维码区域 =====
                _buildQrCodeSection(theme),

                const SizedBox(height: 20),

                // ===== 登录方式切换按钮 =====
                _buildMethodSwitcher(theme),

                const SizedBox(height: 20),

                // ===== 分割线 =====
                _buildDivider(theme),

                const SizedBox(height: 20),

                // ===== 游客模式按钮 =====
                _buildGuestButton(theme, userProvider),

                const SizedBox(height: 24),

                // ===== 退出登录按钮（已登录用户） =====
                if (!userProvider.isGuestMode)
                  _buildLogoutButton(theme, userProvider),

                if (!userProvider.isGuestMode) const SizedBox(height: 20),

                // ===== 隐私说明 =====
                _buildPrivacyNotice(theme),

                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建APP头部（Logo + 名称）
  Widget _buildAppHeader(ThemeData theme) {
    return Column(
      children: [
        // Logo图标
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.primary,
                theme.colorScheme.secondary,
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.play_circle_fill,
            color: Colors.white,
            size: 40,
          ),
        ),
        const SizedBox(height: 12),
        // APP名称
        Text(
          '罐子',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        // 副标题
        Text(
          '登录账号，同步您的数据',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.hintColor,
          ),
        ),
      ],
    );
  }

  /// 构建二维码区域
  Widget _buildQrCodeSection(ThemeData theme) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _currentMethod.brandColor.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            // 二维码标题
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _currentMethod.brandIcon,
                  color: _currentMethod.brandColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  '${_currentMethod.displayName}扫码登录',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 二维码图片
            _buildQrCodeImage(theme),

            const SizedBox(height: 16),

            // 二维码提示文字
            Text(
              _isLoggingIn
                  ? '正在验证登录...'
                  : _isQrExpired
                      ? '二维码已过期，请点击刷新'
                      : _currentMethod.qrHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: _isQrExpired
                    ? Colors.red
                    : _isLoggingIn
                        ? _currentMethod.brandColor
                        : theme.hintColor,
              ),
            ),

            // 二维码有效期提示
            if (!_isQrExpired && !_isLoggingIn)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '二维码有效期：${_refreshCountdown}s',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.hintColor.withValues(alpha: 0.6),
                    fontSize: 11,
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // 操作按钮行
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 刷新二维码
                TextButton.icon(
                  onPressed: _isLoggingIn ? null : _generateQrCode,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('刷新二维码'),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.hintColor,
                  ),
                ),
                const SizedBox(width: 16),
                // 模拟扫码按钮（仅用于演示）
                FilledButton.icon(
                  onPressed:
                      _isLoggingIn || _isQrExpired ? null : _performQrLogin,
                  icon: _isLoggingIn
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.onPrimary,
                          ),
                        )
                      : const Icon(Icons.qr_code_scanner, size: 16),
                  label: Text(_isLoggingIn ? '验证中...' : '扫码登录'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _currentMethod.brandColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建二维码图片
  Widget _buildQrCodeImage(ThemeData theme) {
    const double qrSize = 200.0;

    if (_isQrExpired) {
      // 二维码已过期，显示遮罩
      return Stack(
        children: [
          // 底层模糊的二维码
          Opacity(
            opacity: 0.3,
            child: _buildQrWidget(qrSize),
          ),
          // 过期遮罩
          Container(
            width: qrSize,
            height: qrSize,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.qr_code_2,
                  size: 48,
                  color: theme.hintColor,
                ),
                const SizedBox(height: 8),
                Text(
                  '二维码已过期',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.hintColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '点击下方刷新',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.hintColor,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (_isLoggingIn) {
      // 登录中，显示加载动画
      return Stack(
        children: [
          Opacity(
            opacity: 0.3,
            child: _buildQrWidget(qrSize),
          ),
          Container(
            width: qrSize,
            height: qrSize,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  color: _currentMethod.brandColor,
                ),
                const SizedBox(height: 12),
                Text(
                  '正在验证...',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: _currentMethod.brandColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // 正常显示二维码
    return _buildQrWidget(qrSize);
  }

  /// 构建二维码Widget
  Widget _buildQrWidget(double size) {
    return Container(
      width: 200,
      height: 200,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: QrImageView(
        data: _qrToken,
        version: QrVersions.auto,
        size: size - 24,
        eyeStyle: QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: _currentMethod.brandColor,
        ),
        dataModuleStyle: QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: _themeBrightness == Brightness.dark
              ? const Color(0xFF333333)
              : const Color(0xFF1A1A1A),
        ),
      ),
    );
  }

  /// 获取当前主题亮度
  Brightness get _themeBrightness {
    return Theme.of(context).brightness;
  }

  /// 构建登录方式切换器
  Widget _buildMethodSwitcher(ThemeData theme) {
    return Row(
      children: [
        // 微信登录按钮
        Expanded(
          child: _buildMethodButton(
            theme: theme,
            method: _LoginMethod.wechat,
            isSelected: _currentMethod == _LoginMethod.wechat,
            onTap: () => _switchMethod(_LoginMethod.wechat),
          ),
        ),
        const SizedBox(width: 12),
        // QQ登录按钮
        Expanded(
          child: _buildMethodButton(
            theme: theme,
            method: _LoginMethod.qq,
            isSelected: _currentMethod == _LoginMethod.qq,
            onTap: () => _switchMethod(_LoginMethod.qq),
          ),
        ),
      ],
    );
  }

  /// 构建单个登录方式按钮（B站风格品牌色圆角按钮）
  Widget _buildMethodButton({
    required ThemeData theme,
    required _LoginMethod method,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected
                ? method.brandColor
                : method.brandColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: isSelected
                ? null
                : Border.all(
                    color: method.brandColor.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                method.brandIcon,
                color: isSelected ? Colors.white : method.brandColor,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                '${method.displayName}登录',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : method.brandColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建分割线
  Widget _buildDivider(ThemeData theme) {
    return Row(
      children: [
        Expanded(child: Divider(color: theme.dividerColor)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '或',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.hintColor,
            ),
          ),
        ),
        Expanded(child: Divider(color: theme.dividerColor)),
      ],
    );
  }

  /// 构建游客模式按钮
  Widget _buildGuestButton(ThemeData theme, UserProvider userProvider) {
    final isCurrent = userProvider.isGuestMode;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          await userProvider.switchToGuest();
          if (!mounted) return;
          context.pop();
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isCurrent
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
            border: isCurrent
                ? Border.all(
                    color: theme.colorScheme.primary,
                    width: 2,
                  )
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.person_outline,
                color: theme.colorScheme.primary,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                '游客模式进入',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
              if (isCurrent) ...[
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '当前',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 构建退出登录按钮
  Widget _buildLogoutButton(ThemeData theme, UserProvider userProvider) {
    return OutlinedButton.icon(
      onPressed: () async {
        // 确认退出对话框
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('确认退出'),
            content: const Text('退出登录后将切换为游客模式，数据不会丢失。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red,
                ),
                child: const Text('确认退出'),
              ),
            ],
          ),
        );

        if (confirmed == true && mounted) {
          await userProvider.logout();
          if (!mounted) return;
          context.pop();
        }
      },
      icon: const Icon(Icons.logout),
      label: const Text('退出登录'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        side: const BorderSide(color: Colors.red),
        foregroundColor: Colors.red,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  /// 构建隐私说明
  Widget _buildPrivacyNotice(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '隐私说明',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '1. 本应用为纯客户端应用，不收集任何个人信息\n'
            '2. 登录仅获取OpenID用于数据同步标识\n'
            '3. 所有影视数据均来自第三方播放源\n'
            '4. 您的收藏、历史等数据仅存储在本地或您的WebDAV空间',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.hintColor,
              height: 1.8,
            ),
          ),
        ],
      ),
    );
  }
}
