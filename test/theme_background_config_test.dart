import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fs_music_app/models/theme_palette.dart';
import 'package:fs_music_app/providers/theme_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// V1.1-3：逐页/逐歌单背景配置测试
///
/// 1) ThemePalette 序列化 round-trip（perPage/perPlaylist 不丢）；
/// 2) ThemeProvider 作用范围解析：精确 → 层级回退（queue:xx → queue →
///    全局；pl:id → 全局）；
/// 3) setPageBackgroundPath / setPageMask 持久化与恢复；
/// 4) 默认共用语义：未单独设置的页面回退全局图。
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
  const globalPath = '/tmp/global.jpg';
  const homePath = '/tmp/home.jpg';
  const plPath = '/tmp/pl.jpg';
  const queueAllPath = '/tmp/queueAll.jpg';

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fs_bg_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('ThemePalette 序列化', () {
    test('perPage/perPlaylist 配置 round-trip 不丢', () {
      final p = ThemePalette();
      p.backgroundImagePath = globalPath;
      p.perPageBackgrounds[ThemePalette.pageKeyHome] =
          PageBackgroundConfig(imagePath: homePath, maskDay: 0.2, maskNight: 0.7);
      p.perPageBackgrounds[ThemePalette.queueSourceAllSongs] =
          PageBackgroundConfig(imagePath: queueAllPath);
      p.perPlaylistBackgrounds['pl1'] =
          PageBackgroundConfig(imagePath: plPath, maskNight: 0.5);

      final loaded = ThemePalette.fromJson(p.toJson());
      expect(loaded.backgroundImagePath, globalPath);
      expect(loaded.perPageBackgrounds[ThemePalette.pageKeyHome]?.imagePath,
          homePath);
      expect(
          loaded.perPageBackgrounds[ThemePalette.pageKeyHome]?.maskDay, 0.2);
      expect(
          loaded.perPageBackgrounds[ThemePalette.pageKeyHome]?.maskNight, 0.7);
      expect(
          loaded.perPageBackgrounds[ThemePalette.queueSourceAllSongs]?.imagePath,
          queueAllPath);
      expect(loaded.perPlaylistBackgrounds['pl1']?.imagePath, plPath);
      expect(loaded.perPlaylistBackgrounds['pl1']?.maskNight, 0.5);
    });

    test('空配置序列化为空（不产生脏数据）', () {
      final p = ThemePalette();
      final loaded = ThemePalette.fromJson(p.toJson());
      expect(loaded.perPageBackgrounds, isEmpty);
      expect(loaded.perPlaylistBackgrounds, isEmpty);
    });
  });

  group('ThemeProvider 作用范围解析', () {
    late ThemeProvider provider;

    setUp(() async {
      provider = ThemeProvider();
      await provider.load();
    });

    test('默认共用：未单独设置的页面回退全局图', () async {
      await provider.setBackgroundImage(globalPath);
      expect(provider.effectiveBackgroundPath(ThemePalette.pageKeyHome),
          globalPath);
      expect(provider.effectiveBackgroundPath(ThemePalette.pageKeySearch),
          globalPath);
      //遮罩回退全局默认（夜间 0.30）
      expect(provider.effectiveBackgroundMask(ThemePalette.pageKeyHome, true),
          0.30);
    });

    test('单独设置页面 → 该页覆盖全局，其他页仍回退全局', () async {
      await provider.setBackgroundImage(globalPath);
      await provider.setPageBackgroundPath(ThemePalette.pageKeyHome, homePath);
      expect(provider.effectiveBackgroundPath(ThemePalette.pageKeyHome),
          homePath);
      expect(provider.effectiveBackgroundPath(ThemePalette.pageKeySearch),
          globalPath);
    });

    test('移除该页配置 → 回退全局', () async {
      await provider.setBackgroundImage(globalPath);
      await provider.setPageBackgroundPath(ThemePalette.pageKeyHome, homePath);
      await provider.setPageBackgroundPath(ThemePalette.pageKeyHome, null);
      expect(provider.effectiveBackgroundPath(ThemePalette.pageKeyHome),
          globalPath);
    });

    test('清除所有页面自定义：全部回退全局，全局背景保留', () async {
      await provider.setBackgroundImage(globalPath);
      await provider.setPageBackgroundPath(ThemePalette.pageKeyHome, homePath);
      await provider.setPageMask(ThemePalette.pageKeyHome,
          isDark: true, alpha: 0.8);
      await provider.setPageBackgroundPath(
          ThemePalette.playlistKey('p1'), plPath);
      expect(provider.hasPageBackgroundOverrides, isTrue);

      await provider.clearAllPageBackgrounds();

      expect(provider.hasPageBackgroundOverrides, isFalse);
      expect(provider.palette.backgroundImagePath, globalPath);
      expect(provider.effectiveBackgroundPath(ThemePalette.pageKeyHome),
          globalPath);
      expect(provider.effectiveBackgroundMask(ThemePalette.pageKeyHome, true),
          0.30);
      expect(provider.effectiveBackgroundPath(ThemePalette.playlistKey('p1')),
          globalPath);
      //落盘后重新加载仍是已清除状态
      final reloaded = ThemeProvider();
      await reloaded.load();
      expect(reloaded.hasPageBackgroundOverrides, isFalse);
      expect(reloaded.effectiveBackgroundPath(ThemePalette.pageKeyHome),
          globalPath);
    });

    test('播放队列源级回退链：源 → queue 板块 → 全局', () async {
      await provider.setBackgroundImage(globalPath);
      //仅全局：主页源回退全局
      expect(provider.effectiveBackgroundPath(ThemePalette.queueSourceAllSongs),
          globalPath);
      //设置 queue 板块（全部播放源）→ 主页源回退到它
      await provider.setPageBackgroundPath(
          ThemePalette.pageKeyQueue, queueAllPath);
      expect(provider.effectiveBackgroundPath(ThemePalette.queueSourceAllSongs),
          queueAllPath);
      //单独设置主页源 → 覆盖 queue 板块
      const qAllPath = '/tmp/qAll.jpg';
      await provider.setPageBackgroundPath(
          ThemePalette.queueSourceAllSongs, qAllPath);
      expect(provider.effectiveBackgroundPath(ThemePalette.queueSourceAllSongs),
          qAllPath);
      //收藏源未设置 → 仍回退 queue 板块
      expect(provider.effectiveBackgroundPath(ThemePalette.queueSourceFavorites),
          queueAllPath);
      //移除 queue 板块 → 收藏源回退全局
      await provider.setPageBackgroundPath(ThemePalette.pageKeyQueue, null);
      expect(provider.effectiveBackgroundPath(ThemePalette.queueSourceFavorites),
          globalPath);
    });

    test('歌单背景：pl:id 精确覆盖 → 移除回退全局', () async {
      await provider.setBackgroundImage(globalPath);
      final key = ThemePalette.playlistKey('pl1');
      expect(provider.effectiveBackgroundPath(key), globalPath);
      await provider.setPageBackgroundPath(key, plPath);
      expect(provider.effectiveBackgroundPath(key), plPath);
      await provider.setPageBackgroundPath(key, null);
      expect(provider.effectiveBackgroundPath(key), globalPath);
    });

    test('遮罩浓度日/夜独立 + 重启持久化', () async {
      await provider.setPageMask(ThemePalette.pageKeyHome,
          isDark: true, alpha: 0.8);
      await provider.setPageMask(ThemePalette.pageKeyHome,
          isDark: false, alpha: 0.4);
      expect(
          provider.effectiveBackgroundMask(ThemePalette.pageKeyHome, true),
          0.8);
      expect(
          provider.effectiveBackgroundMask(ThemePalette.pageKeyHome, false),
          0.4);

      //重启（新实例 load）恢复
      final provider2 = ThemeProvider();
      await provider2.load();
      expect(
          provider2.effectiveBackgroundMask(ThemePalette.pageKeyHome, true),
          0.8);
      expect(
          provider2.effectiveBackgroundMask(ThemePalette.pageKeyHome, false),
          0.4);
    });

    test('仅调遮罩未选图：图片回退全局、遮罩用本页值', () async {
      await provider.setBackgroundImage(globalPath);
      await provider.setPageMask(ThemePalette.pageKeySearch,
          isDark: true, alpha: 0.9);
      expect(provider.effectiveBackgroundPath(ThemePalette.pageKeySearch),
          globalPath);
      expect(
          provider.effectiveBackgroundMask(ThemePalette.pageKeySearch, true),
          0.9);
    });
  });
}
