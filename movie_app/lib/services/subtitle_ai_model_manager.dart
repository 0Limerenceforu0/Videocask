// ignore_for_file: prefer_const_constructors

import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'subtitle_ai_backend.dart';

/// 单个可下载的离线模型
class SubtitleAiModel {
  final String id;
  final String displayName;
  final String description;
  final String engineKind; // 'whisper' / 'paraformer' / 'sense_voice' / 'zipformer_ctc'
  final String sherpaModelType; // sherpa_onnx modelType 字段
  final String archiveUrl; // .tar.bz2
  final List<String> requiredFiles; // 抽出来后需要的文件名
  final int approxSizeMb;
  final List<String> supportedLanguages;

  const SubtitleAiModel({
    required this.id,
    required this.displayName,
    required this.description,
    required this.engineKind,
    required this.sherpaModelType,
    required this.archiveUrl,
    required this.requiredFiles,
    required this.approxSizeMb,
    required this.supportedLanguages,
  });

  String get archiveFileName {
    final u = Uri.parse(archiveUrl);
    return u.pathSegments.last;
  }
}

/// 内置可识别的离线模型注册表
class SubtitleAiModelRegistry {
  static final SubtitleAiModelRegistry _instance =
      SubtitleAiModelRegistry._internal();
  factory SubtitleAiModelRegistry() => _instance;
  SubtitleAiModelRegistry._internal() {
    _models.addAll(_builtin());
  }

  final List<SubtitleAiModel> _models = [];

  Iterable<SubtitleAiModel> get all => List.unmodifiable(_models);

  SubtitleAiModel? findById(String id) {
    for (final m in _models) {
      if (m.id == id) return m;
    }
    return null;
  }

  List<SubtitleAiModel> _builtin() {
    return const [
      // 中文首选：Paraformer
      SubtitleAiModel(
        id: 'sherpa-onnx-paraformer-zh-2024-03-09',
        displayName: 'Paraformer 中文+英文+方言',
        description: 'FunASR 训练的非自回归模型，中文识别准确度高，速度比 Whisper 快',
        engineKind: 'paraformer',
        sherpaModelType: 'paraformer',
        archiveUrl:
            'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-paraformer-zh-2024-03-09.tar.bz2',
        requiredFiles: ['model.onnx', 'tokens.txt'],
        approxSizeMb: 230,
        supportedLanguages: ['zh', 'en', 'zh-yue'],
      ),
      // 多语言多方言：SenseVoice
      SubtitleAiModel(
        id: 'sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17',
        displayName: 'SenseVoice 多语多方言',
        description: '中/英/粤/日/韩 + 多种中文方言，识别速度快',
        engineKind: 'sense_voice',
        sherpaModelType: 'sense_voice',
        archiveUrl:
            'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17.tar.bz2',
        requiredFiles: ['model.int8.onnx', 'tokens.txt'],
        approxSizeMb: 230,
        supportedLanguages: ['zh', 'en', 'ja', 'ko', 'yue'],
      ),
      // 轻量中文：Zipformer CTC int8
      SubtitleAiModel(
        id: 'sherpa-onnx-zipformer-ctc-zh-int8-2025-07-03',
        displayName: 'Zipformer CTC 中文（轻量）',
        description: '仅中文、int8 量化，体积最小，速度快，准确度中等',
        engineKind: 'zipformer_ctc',
        sherpaModelType: 'zipformer2_ctc',
        archiveUrl:
            'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-zipformer-ctc-zh-int8-2025-07-03.tar.bz2',
        requiredFiles: ['model.int8.onnx', 'tokens.txt'],
        approxSizeMb: 100,
        supportedLanguages: ['zh'],
      ),
      // Whisper tiny multilingual
      SubtitleAiModel(
        id: 'sherpa-onnx-whisper-tiny',
        displayName: 'Whisper tiny 多语言',
        description: 'OpenAI Whisper tiny 多语种，体积最小，速度最快，准确度一般',
        engineKind: 'whisper',
        sherpaModelType: 'whisper',
        archiveUrl:
            'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny.tar.bz2',
        requiredFiles: ['tiny-encoder.onnx', 'tiny-decoder.onnx', 'tokens.txt'],
        approxSizeMb: 75,
        supportedLanguages: ['zh', 'en', 'ja', 'ko', 'es', 'fr', 'de'],
      ),
      // Whisper base multilingual
      SubtitleAiModel(
        id: 'sherpa-onnx-whisper-base',
        displayName: 'Whisper base 多语言',
        description: 'OpenAI Whisper base 多语种，平衡准确度与体积',
        engineKind: 'whisper',
        sherpaModelType: 'whisper',
        archiveUrl:
            'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-base.tar.bz2',
        requiredFiles: ['base-encoder.onnx', 'base-decoder.onnx', 'tokens.txt'],
        approxSizeMb: 150,
        supportedLanguages: ['zh', 'en', 'ja', 'ko', 'es', 'fr', 'de'],
      ),
      // Web 端：transformers.js Whisper base（浏览器端下载）
      SubtitleAiModel(
        id: 'web-whisper-base',
        displayName: 'Whisper base（浏览器端）',
        description: '通过 transformers.js 在浏览器内运行，首次使用自动下载到 OPFS',
        engineKind: 'whisper_web',
        sherpaModelType: '',
        archiveUrl: '',
        requiredFiles: [],
        approxSizeMb: 150,
        supportedLanguages: ['zh', 'en', 'ja', 'ko'],
      ),
    ];
  }
}

/// 全局注册表访问入口
final kSubtitleAiModelRegistry = SubtitleAiModelRegistry();

/// 模型本地可用性 + 安装路径解析
extension SubtitleAiModelLocal on SubtitleAiModel {
  /// 模型解压目录
  Future<Directory> modelDir() async {
    final base = await _modelsRoot();
    return Directory('${base.path}${Platform.pathSeparator}$id');
  }

  /// 模型是否已下载并解压
  Future<bool> get isLocallyAvailable async {
    if (engineKind == 'whisper_web') {
      // Web 端模型由 transformers.js 管理，不走这里
      return true;
    }
    final dir = await modelDir();
    if (!dir.existsSync()) return false;
    for (final name in requiredFiles) {
      final f = File('${dir.path}${Platform.pathSeparator}$name');
      if (!f.existsSync()) return false;
    }
    return true;
  }

  Future<int> get localSizeBytes async {
    if (engineKind == 'whisper_web') return 0;
    final dir = await modelDir();
    if (!dir.existsSync()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  static Future<Directory> _modelsRoot() async {
    if (kIsWeb) return Directory('/'); // Web 不用
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory(
      '${docs.path}${Platform.pathSeparator}subtitle_ai_models',
    );
    if (!root.existsSync()) {
      root.createSync(recursive: true);
    }
    return root;
  }
}

/// 模型下载 / 解压 / 删除
class SubtitleAiModelInstaller {
  static final SubtitleAiModelInstaller _instance =
      SubtitleAiModelInstaller._internal();
  factory SubtitleAiModelInstaller() => _instance;
  SubtitleAiModelInstaller._internal();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 30),
    ),
  );

  Future<SubtitleAiResult> download(
    SubtitleAiModel model, {
    required void Function(double progress, String message) onProgress,
  }) async {
    if (model.engineKind == 'whisper_web') {
      throw SubtitleAiException('浏览器端模型无需手动下载');
    }
    final base = await _modelsRoot();
    final archivePath =
        '${base.path}${Platform.pathSeparator}${model.archiveFileName}';
    final targetDir = await model.modelDir();

    onProgress(0.0, '开始下载 ${model.displayName}');
    await _dio.download(
      model.archiveUrl,
      archivePath,
      onReceiveProgress: (rec, total) {
        if (total > 0) {
          onProgress(
            (rec / total) * 0.7,
            '下载 ${(rec * 100 ~/ total)}% (${(rec / 1024 / 1024).toStringAsFixed(1)}MB / ${(total / 1024 / 1024).toStringAsFixed(1)}MB)',
          );
        }
      },
    );

    onProgress(0.75, '解压中…');
    if (targetDir.existsSync()) {
      targetDir.deleteSync(recursive: true);
    }
    targetDir.createSync(recursive: true);

    final archiveBytes = await File(archivePath).readAsBytes();
    final decompressed = BZip2Decoder().decodeBytes(archiveBytes);
    final tarDecoder = TarDecoder();
    final tarArchive = tarDecoder.decodeBytes(decompressed);

    var total = tarArchive.files.length;
    var done = 0;
    for (final f in tarArchive.files) {
      final out = '${targetDir.path}${Platform.pathSeparator}${f.name}';
      if (f.isFile) {
        final outFile = File(out);
        outFile.parent.createSync(recursive: true);
        outFile.writeAsBytesSync(f.content as List<int>);
      } else {
        Directory(out).createSync(recursive: true);
      }
      done++;
      onProgress(
        0.75 + 0.20 * (done / total),
        '解压 ${done}/${total}',
      );
    }

    onProgress(0.97, '清理临时文件');
    try {
      await File(archivePath).delete().catchError((_) => File(archivePath));
    } catch (_) {}

    onProgress(1.0, '下载完成');
    return SubtitleAiResult(
      srtContent: '',
      plainText: '已安装 ${model.displayName}',
      usedDuration: Duration.zero,
      elapsed: Duration.zero,
      backend: SubtitleAiBackendKind.sherpaNative,
    );
  }

  Future<void> delete(SubtitleAiModel model) async {
    if (model.engineKind == 'whisper_web') return;
    final dir = await model.modelDir();
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  }

  static Future<Directory> _modelsRoot() async {
    if (kIsWeb) return Directory('/');
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory(
      '${docs.path}${Platform.pathSeparator}subtitle_ai_models',
    );
    if (!root.existsSync()) {
      root.createSync(recursive: true);
    }
    return root;
  }
}