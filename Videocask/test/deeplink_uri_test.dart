import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/config/routes.dart';

void main() {
  test('DeepLink 详情 URI 应对特殊字符正确编码', () {
    const id = 'abc&def=1';
    const sourceId = 'src/1';
    final uri = Uri(
      path: AppRoutes.detail,
      queryParameters: <String, String>{
        'id': id,
        'sourceId': sourceId,
      },
    );
    expect(uri.queryParameters['id'], id);
    expect(uri.queryParameters['sourceId'], sourceId);
    expect(uri.toString(), contains(Uri.encodeQueryComponent(id)));
  });

  test('DeepLink 搜索 URI 空关键词不产生多余 query', () {
    final empty = Uri(
      path: AppRoutes.search,
      queryParameters: null,
    );
    expect(empty.query, isEmpty);

    const q = '三体 & 合集';
    final withQuery = Uri(
      path: AppRoutes.search,
      queryParameters: <String, String>{'query': q},
    );
    expect(withQuery.queryParameters['query'], q);
  });
}
