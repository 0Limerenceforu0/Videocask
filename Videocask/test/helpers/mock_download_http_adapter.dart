import 'dart:typed_data';

import 'package:dio/dio.dart';

/// 按 URL 关键字返回固定字节的 Dio 适配器（用于下载单测）。
class MockDownloadHttpAdapter implements HttpClientAdapter {
  MockDownloadHttpAdapter({
    this.defaultBytes = const [],
    this.statusCode = 200,
    this.failUrls = const {},
    Map<String, List<int>>? urlBytes,
  }) : _urlBytes = urlBytes ?? {};

  final List<int> defaultBytes;
  final int statusCode;
  final Set<String> failUrls;
  final Map<String, List<int>> _urlBytes;

  int fetchCount = 0;
  final List<String> fetchedUrls = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    fetchCount++;
    final url = options.uri.toString();
    fetchedUrls.add(url);

    for (final fail in failUrls) {
      if (url.contains(fail)) {
        return ResponseBody.fromString(
          'forbidden',
          403,
          headers: {
            Headers.contentTypeHeader: ['text/plain'],
          },
        );
      }
    }

    List<int> bytes = defaultBytes;
    for (final entry in _urlBytes.entries) {
      if (url.contains(entry.key)) {
        bytes = entry.value;
        break;
      }
    }

    final data = Uint8List.fromList(bytes);
    return ResponseBody.fromBytes(
      data,
      statusCode,
      headers: {
        Headers.contentLengthHeader: [data.length.toString()],
      },
    );
  }
}

List<int> bytesOfLength(int length, {int fill = 7}) {
  return List<int>.filled(length, fill);
}
