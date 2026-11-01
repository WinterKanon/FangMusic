import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fs_music_app/models/list_sort_mode.dart';
import 'package:fs_music_app/services/list_view_prefs_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  final prefs = ListViewPrefsService.instance;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fs_list_prefs_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    SharedPreferences.setMockInitialValues({});
    prefs.resetForTest();
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('默认排序：主页添加时间倒序、收藏/歌单来源顺序', () async {
    await prefs.load();
    expect(prefs.sortFor(ListViewPrefsService.keyHome),
        ListSortMode.addTimeDesc);
    expect(prefs.sortFor(ListViewPrefsService.keyFavorites),
        ListSortMode.sourceOrder);
    expect(prefs.sortFor(ListViewPrefsService.keyForPlaylist('p1')),
        ListSortMode.sourceOrder);
  });

  test('排序与自定义顺序持久化、重启恢复', () async {
    await prefs.load();
    await prefs.setSort(ListViewPrefsService.keyHome, ListSortMode.nameAsc);
    await prefs.setCustomOrder(
        ListViewPrefsService.keyHome, ['/a.mp3', '/b.mp3']);
    prefs.resetForTest();
    await prefs.load();
    expect(prefs.sortFor(ListViewPrefsService.keyHome),
        ListSortMode.custom);
    expect(prefs.customOrderFor(ListViewPrefsService.keyHome),
        ['/a.mp3', '/b.mp3']);
  });

  test('旧 sort_mode 迁移：歌名 → nameAsc', () async {
    SharedPreferences.setMockInitialValues({'sort_mode': 'name'});
    await prefs.load();
    expect(prefs.sortFor(ListViewPrefsService.keyHome),
        ListSortMode.nameAsc);
  });
}
