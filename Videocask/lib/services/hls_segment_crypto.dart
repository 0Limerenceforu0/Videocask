import 'dart:io';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';

import 'm3u8_playlist_resolver.dart';

/// HLS AES-128 分片解密。
class HlsSegmentCrypto {
  HlsSegmentCrypto._();

  static Future<Uint8List> loadKeyBytes(
    M3u8Aes128Key keyInfo, {
    required Map<String, String> headers,
  }) async {
    final http = await _fetchBytes(keyInfo.uri, headers);
    if (http.length != 16) {
      throw StateError('Invalid AES-128 key length: ${http.length}');
    }
    return http;
  }

  static Future<Uint8List> _fetchBytes(
    String url,
    Map<String, String> headers,
  ) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      headers.forEach(request.headers.set);
      final response = await request.close();
      return consolidateHttpClientResponseBytes(response);
    } finally {
      client.close();
    }
  }

  static Uint8List decryptSegment({
    required Uint8List encrypted,
    required Uint8List keyBytes,
    required int segmentIndex,
    String? ivHex,
  }) {
    final iv = _ivForSegment(segmentIndex, ivHex);
    final encrypter = enc.Encrypter(
      enc.AES(enc.Key(keyBytes), mode: enc.AESMode.cbc, padding: null),
    );
    final decrypted = encrypter.decryptBytes(
      enc.Encrypted(encrypted),
      iv: enc.IV(iv),
    );
    return Uint8List.fromList(_removePkcs7(decrypted));
  }

  static Uint8List _ivForSegment(int segmentIndex, String? ivHex) {
    if (ivHex != null && ivHex.isNotEmpty) {
      final hex = ivHex.padLeft(32, '0');
      final bytes = Uint8List(16);
      for (var i = 0; i < 16; i++) {
        bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
      }
      return bytes;
    }
    final bytes = Uint8List(16);
    final indexBytes = ByteData(8)..setUint64(0, segmentIndex);
    bytes.setRange(8, 16, indexBytes.buffer.asUint8List());
    return bytes;
  }

  static List<int> _removePkcs7(List<int> data) {
    if (data.isEmpty) return data;
    final pad = data.last;
    if (pad <= 0 || pad > 16) return data;
    for (var i = data.length - pad; i < data.length; i++) {
      if (data[i] != pad) return data;
    }
    return data.sublist(0, data.length - pad);
  }
}
