import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models/song.dart';
import 'storage_service.dart';

/// 扫描结果摘要
class ScanResult {
  final int added; //新增数
  final int removed; //移除数（该目录下已不存在的文件，从库中清除）
  final int skipped; //跳过数（已在库中）
  final int failed; //失败数
  const ScanResult({
    this.added = 0,
    this.removed = 0,
    this.skipped = 0,
    this.failed = 0,
  });
}

/// 文件夹扫描服务：选择文件夹 → 扫描其中音频（不递归）→ 与库同步 → 写库
///
/// 设计说明（按用户需求）：
/// - 用户手动指定手机中的一个文件夹（可自行创建），**不递归**子文件夹
/// - 文件夹中有多少音频文件，库中就对齐多少：新增新文件、移除已删除文件、跳过未变化
/// - 直接使用原文件路径，**不复制**文件，不占双倍空间
/// - 所有读写最终都走 [StorageService]
class AudioScannerService {
  /// 获取时长的并发数（避免同时创建过多 AudioPlayer 导致原生层异常）
  static const _concurrency = 4;

  /// 支持的音频扩展名（just_audio 可播放的常见格式）
  static const _audioExts = {
    '.mp3',
    '.wav',
    '.flac',
    '.m4a',
    '.aac',
    '.ogg',
    '.opus',
    '.wma',
    '.amr',
  };

  /// 调用系统文件夹选择器；返回可访问的真实目录路径，用户取消返回 null
  static Future<String?> pickDirectory() async {
    final uri = await FilePicker.platform.getDirectoryPath();
    //调试用：排查"选完文件夹解析失败"问题时，可在控制台查看原始返回值
    debugPrint('[scan] 文件夹选择器返回: $uri');
    if (uri == null || uri.isEmpty) return null;
    return resolveDirectoryPath(uri);
  }

  /// 将 Android 文件夹选择器返回的 URI 解析为真实文件系统路径
  ///
  /// 例：`content://com.android.externalstorage.documents/tree/primary%3AMusic`
  ///   → `/storage/emulated/0/Music`
  /// 注意：Uri.parse 会自动把 `%3A` 解码为 `:`，
  /// 因此这里直接查找 `:`（同时兼容未编码形式）。
  /// 仅支持手机内部存储（primary）；SD 卡（secondary）等无法映射时返回 null
  static String? resolveDirectoryPath(String uri) {
    //已经是真实文件路径，直接返回
    if (uri.startsWith('/')) return uri;
    final u = Uri.tryParse(uri);
    if (u == null) return null;
    if (u.host == 'com.android.externalstorage.documents' &&
        u.pathSegments.length >= 2 &&
        u.pathSegments[0] == 'tree') {
      final treeId = u.pathSegments[1]; //解码后形如 primary:Music 或 primary:（根）
      final sep = treeId.indexOf(':');
      if (sep > 0 && treeId.startsWith('primary')) {
        final sub = treeId.substring(sep + 1);
        return '/storage/emulated/0/${sub.isEmpty ? '' : sub}';
      }
    }
    return null;
  }

  /// 扫描指定文件夹并同步歌曲库
  ///
  /// 对齐规则：
  /// - 库中路径以该目录开头的记录，若文件已不存在 → 移除
  /// - 目录中的音频文件，已在库中 → 跳过；不在库中 → 新增（探测时长）
  static Future<ScanResult> scanDirectory(
    String dirPath, {
    void Function(int current, int total)? onProgress,
  }) async {
    //1. 列出目录下所有音频文件（不递归子文件夹）
    final files = <File>[];
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        return const ScanResult(failed: 1);
      }
      await for (final entry in dir.list(followLinks: false)) {
        if (entry is File && _audioExts.contains(p.extension(entry.path).toLowerCase())) {
          files.add(entry);
        }
      }
    } catch (_) {
      //目录无权限读取等
      return const ScanResult(failed: 1);
    }
    //记录本次选择的文件夹（v1.1-5：设置→所选文件夹管理；空文件夹也记录，
    //便于用户查看/移除）。重复选择同一文件夹不会重复添加。
    await StorageService.addMusicFolder(dirPath);
    if (files.isEmpty) return const ScanResult();

    final existing = await StorageService.loadSongs();
    final byPath = <String, Song>{
      for (final e in existing) e.audioFilePath: e,
    };
    final prefix =
        dirPath.endsWith('/') || dirPath.endsWith('\\') ? dirPath : '$dirPath/';

    //2. 移除：该目录下已不存在的记录
    final kept = <Song>[];
    int removed = 0;
    for (final e in existing) {
      final isInDir = e.audioFilePath.startsWith(prefix);
      final stillExists = files.any((f) => f.path == e.audioFilePath);
      if (isInDir && !stillExists) {
        removed++; //该目录下文件已被删除 → 从库移除
      } else {
        kept.add(e);
      }
    }

    //3. 新增/跳过：目录中与库的差异
    final toAdd = <File>[];
    int skipped = 0;
    for (final f in files) {
      if (byPath.containsKey(f.path)) {
        skipped++;
      } else {
        toAdd.add(f);
      }
    }

    //4. 并发探测新增文件的时长
    final durations = await _mapWithConcurrency<File, int>(
      toAdd,
      _concurrency,
      (f) => _probeDuration(f.path),
      onProgress,
    );

    //5. 组装新记录并写库
    int nextSort = existing.isEmpty
        ? 1
        : (existing.map((e) => e.sortNumber).reduce((a, b) => a > b ? a : b) +
            1);
    //v1.2：同一批歌曲的 addTime 递增 1ms，保证"按添加时间"排序有稳定次序
    final baseTime = DateTime.now();
    final newItems = <Song>[];
    int added = 0, failed = 0;
    for (var i = 0; i < toAdd.length; i++) {
      final f = toAdd[i];
      try {
        final fileSize = await f.length();
        newItems.add(Song(
          name: p.basenameWithoutExtension(f.path).trim(),
          audioFilePath: f.path,
          addTime: baseTime.add(Duration(milliseconds: i)).toIso8601String(),
          duration: durations[i] ?? 0,
          fileSize: fileSize,
          sortNumber: nextSort++,
        ));
        added++;
      } catch (_) {
        failed++;
      }
    }

    await StorageService.saveSongs([...kept, ...newItems]);
    return ScanResult(added: added, removed: removed, skipped: skipped, failed: failed);
  }

  //==================== 内部工具 ====================

  /// 探测音频时长（毫秒），失败或超时返回 0。
  ///
  /// 走 Android 原生 MediaMetadataRetriever（见 MainActivity 的平台通道），
  /// **不创建 AudioPlayer**：just_audio_background 全局只允许一个播放器实例，
  /// 扫描探测不能再建播放器，否则会抛 "single player instance"。
  static const _durationChannel = MethodChannel('fs_music/metadata');

  static Future<int> _probeDuration(String filePath) async {
    try {
      final ms = await _durationChannel
          .invokeMethod<int>('getDuration', {'path': filePath})
          .timeout(const Duration(seconds: 5));
      return ms ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// 简单并发池：限制同时执行的任务数，单个失败不影响其他
  static Future<List<R?>> _mapWithConcurrency<T, R>(
    List<T> items,
    int concurrency,
    Future<R> Function(T) fn,
    void Function(int current, int total)? onProgress,
  ) async {
    final results = List<R?>.filled(items.length, null);
    int index = 0, done = 0;
    Future<void> worker() async {
      while (index < items.length) {
        final i = index++;
        try {
          results[i] = await fn(items[i]);
        } catch (_) {
          //保持 null，调用方用 ?? 兜底
        }
        done++;
        onProgress?.call(done, items.length);
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));
    return results;
  }
}
