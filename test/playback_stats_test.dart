import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fs_music_app/services/playback_stats_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  final Directory dir;
  _FakePathProvider(this.dir);

  @override
  Future<String?> getApplicationDocumentsPath() async => dir.path;

  @override
  Future<String?> getApplicationSupportPath() async => dir.path;

  @override
  Future<String?> getTemporaryPath() async => dir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  final stats = PlaybackStatsService.instance;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fs_play_stats_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    stats.resetForTest();
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('播放计数：累加并持久化', () async {
    await stats.load();
    await stats.recordStart('/music/a.mp3');
    await stats.recordStart('/music/a.mp3');
    expect(stats.countOf('/music/a.mp3'), 2);
    stats.resetForTest();
    await stats.load();
    expect(stats.countOf('/music/a.mp3'), 2);
  });

  test('永久删除清理统计', () async {
    await stats.load();
    await stats.recordStart('/music/a.mp3');
    await stats.recordStart('/music/b.mp3');
    await stats.removePaths(['/music/a.mp3']);
    expect(stats.countOf('/music/a.mp3'), 0);
    expect(stats.countOf('/music/b.mp3'), 1);
  });
}
