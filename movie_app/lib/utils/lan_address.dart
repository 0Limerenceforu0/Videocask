import 'dart:io';

/// 获取本机局域网 IPv4，供 DLNA / 本地 HTTP 服务使用。
class LanAddress {
  LanAddress._();

  static Future<String?> preferredIPv4() async {
    if (!Platform.isAndroid && !Platform.isIOS) return null;
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (_isPrivateLan(ip)) return ip;
        }
      }
    } catch (_) {}
    return null;
  }

  static bool _isPrivateLan(String ip) {
    if (ip.startsWith('192.168.')) return true;
    if (ip.startsWith('10.')) return true;
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final second = int.tryParse(parts[1]);
    if (second == null) return false;
    return parts[0] == '172' && second >= 16 && second <= 31;
  }

  /// 将 localhost / 127.0.0.1 替换为局域网地址。
  static String rewriteLocalHost(String url, String lanIp) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return url;
    final host = uri.host.toLowerCase();
    if (host != 'localhost' && host != '127.0.0.1' && host != '0.0.0.0') {
      return url;
    }
    return uri.replace(host: lanIp).toString();
  }
}
