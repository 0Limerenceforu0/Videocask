import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:movie_app/models/movie.dart';

void main() {
  group('Movie.fromCmsJson playRoutes', () {
    test('splits multiple url blocks when play_from is a single player id', () {
      final movie = Movie.fromCmsJson({
        'vod_id': '1',
        'vod_name': '测试',
        'vod_play_from': 'lzm3u8',
        'vod_play_url':
            '第1集\$http://cdn1.example/a.m3u8#第2集\$http://cdn1.example/b.m3u8\$\$\$第1集\$http://cdn2.example/a.m3u8',
      });

      expect(movie.playRoutes.length, 2);
      expect(movie.playRoutes[0].name, 'lzm3u8');
      expect(movie.playRoutes[1].name, 'lzm3u8 2');
      expect(movie.playRoutes[0].episodes.length, 2);
      expect(movie.playRoutes[1].episodes.length, 1);
    });

    test('splits play_from by comma when multiple players are listed', () {
      final movie = Movie.fromCmsJson({
        'vod_id': '2',
        'vod_name': '测试',
        'vod_play_from': 'youku,qiyi',
        'vod_play_url':
            '正片\$http://youku.example/v.m3u8\$\$\$正片\$http://qiyi.example/v.m3u8',
      });

      expect(movie.playRoutes.length, 2);
      expect(movie.playRoutes[0].name, 'youku');
      expect(movie.playRoutes[1].name, 'qiyi');
    });

    test('parses structured vod_play_list when present', () {
      final movie = Movie.fromCmsJson({
        'vod_id': '3',
        'vod_name': '测试',
        'vod_play_from': 'ignored',
        'vod_play_url': 'ignored',
        'vod_play_list': [
          {
            'from': '线路A',
            'urls': [
              {'name': '第1集', 'url': 'http://a.example/1.m3u8'},
              {'name': '第2集', 'url': 'http://a.example/2.m3u8'},
            ],
          },
          {
            'from': '线路B',
            'urls': [
              {'name': '第1集', 'url': 'http://b.example/1.m3u8'},
            ],
          },
        ],
      });

      expect(movie.playRoutes.length, 2);
      expect(movie.playRoutes[0].name, '线路A');
      expect(movie.playRoutes[0].episodes.length, 2);
      expect(movie.playRoutes[1].name, '线路B');
    });
    test('prefers classic vod_play_url when vod_play_list has fewer routes',
        () {
      final movie = Movie.fromCmsJson({
        'vod_id': '4',
        'vod_name': '测试',
        'vod_play_from': 'lzm3u8',
        'vod_play_url':
            '第1集\$http://cdn1.example/a.m3u8#第2集\$http://cdn1.example/b.m3u8\$\$\$第1集\$http://cdn2.example/a.m3u8',
        'vod_play_list': [
          {
            'from': '默认',
            'urls': [
              {'name': '第1集', 'url': 'http://only.example/1.m3u8'},
            ],
          },
        ],
      });

      expect(movie.playRoutes.length, 2);
      expect(movie.playRoutes[0].episodes.length, 2);
      expect(movie.playRoutes[1].episodes.length, 1);
    });

    test('parses vod_play_list JSON string', () {
      final movie = Movie.fromCmsJson({
        'vod_id': '5',
        'vod_name': '测试',
        'vod_play_list': jsonEncode([
          {
            'from': 'A',
            'urls': [
              {'name': '第1集', 'url': 'http://a.example/1.m3u8'},
            ],
          },
          {
            'from': 'B',
            'urls': [
              {'name': '第1集', 'url': 'http://b.example/1.m3u8'},
            ],
          },
        ]),
      });

      expect(movie.playRoutes.length, 2);
      expect(movie.playRoutes[0].name, 'A');
      expect(movie.playRoutes[1].name, 'B');
    });

    test('splits url blocks by double-dollar when play_from has multiple', () {
      final movie = Movie.fromCmsJson({
        'vod_id': '6',
        'vod_name': '测试',
        'vod_play_from': 'youku,qiyi',
        'vod_play_url':
            '正片\$http://youku.example/v.m3u8\$\$正片\$http://qiyi.example/v.m3u8',
      });

      expect(movie.playRoutes.length, 2);
    });
  });
}
