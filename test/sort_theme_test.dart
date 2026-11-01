import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fs_music_app/models/song.dart';
import 'package:fs_music_app/models/sort_mode.dart';
import 'package:fs_music_app/providers/library_provider.dart';
import 'package:fs_music_app/providers/theme_provider.dart';

/// 阶段5 排序 / 主题色逻辑测试（纯内存，不依赖平台通道）
void main() {
  Song makeSong(
    String path, {
    String name = '',
    String addTime = '',
    int duration = 0,
    int sortNumber = 0,
  }) {
    return Song(
      name: name,
      audioFilePath: path,
      sortNumber: sortNumber,
      addTime: addTime,
      duration: duration,
    );
  }

  group('排序（LibraryProvider.sortBy 纯函数）', () {
    test('按添加时间升序', () {
      final songs = [
        makeSong('/a', addTime: '2026-03-01T00:00:00.000', sortNumber: 3),
        makeSong('/b', addTime: '2026-01-01T00:00:00.000', sortNumber: 1),
        makeSong('/c', addTime: '2026-02-01T00:00:00.000', sortNumber: 2),
      ];
      final sorted = LibraryProvider.sortBy(songs, SortMode.addTime);
      expect(
        sorted.map((s) => s.audioFilePath).toList(),
        ['/b', '/c', '/a'],
      );
    });

    test('按歌名排序', () {
      final songs = [
        makeSong('/a', name: 'banana', sortNumber: 1),
        makeSong('/b', name: 'apple', sortNumber: 2),
        makeSong('/c', name: 'cherry', sortNumber: 3),
      ];
      final sorted = LibraryProvider.sortBy(songs, SortMode.name);
      expect(sorted.map((s) => s.name).toList(), ['apple', 'banana', 'cherry']);
    });

    test('按时长升序', () {
      final songs = [
        makeSong('/a', duration: 3000, sortNumber: 1),
        makeSong('/b', duration: 1000, sortNumber: 2),
        makeSong('/c', duration: 2000, sortNumber: 3),
      ];
      final sorted = LibraryProvider.sortBy(songs, SortMode.duration);
      expect(sorted.map((s) => s.audioFilePath).toList(), ['/b', '/c', '/a']);
    });

    test('相同键值时按 sortNumber 次级保持稳定', () {
      final songs = [
        makeSong('/a', name: 'same', sortNumber: 3),
        makeSong('/b', name: 'same', sortNumber: 1),
        makeSong('/c', name: 'same', sortNumber: 2),
      ];
      final sorted = LibraryProvider.sortBy(songs, SortMode.name);
      expect(sorted.map((s) => s.audioFilePath).toList(), ['/b', '/c', '/a']);
    });

    test('纯函数：不修改传入列表', () {
      final songs = [
        makeSong('/b', name: 'b', sortNumber: 1),
        makeSong('/a', name: 'a', sortNumber: 2),
      ];
      final before = songs.map((s) => s.audioFilePath).toList();
      LibraryProvider.sortBy(songs, SortMode.name);
      expect(songs.map((s) => s.audioFilePath).toList(), before);
    });
  });

  group('主题色（ThemeProvider）', () {
    final theme = ThemeProvider();

    test('11 色系：每系 5~10 色、色名齐全、默认紫色、扁平 presets 一致', () {
      final groups = ThemeProvider.presetGroups;
      expect(groups.length, 11); //黑色系/白色系已移除（日夜间逻辑瑕疵）
      var total = 0;
      for (final g in groups) {
        expect(g.name, isNotEmpty);
        expect(g.colors.length, inInclusiveRange(5, 10));
        for (final c in g.colors) {
          expect(c.name, isNotEmpty); //每种颜色都有中文名标注
          expect(ThemeProvider.presetNames[c.color.toARGB32()], c.name);
        }
        total += g.colors.length;
      }
      //扁平 presets 与色系总颜色数一致（setPresetSeed 校验用）
      expect(ThemeProvider.presets.length, total);
      expect(theme.seedColor(), const Color(0xFF7C4DFF)); //默认紫
    });

    test('setPresetSeed 切换生效（内存），无效颜色忽略', () async {
      await theme.setPresetSeed(const Color(0xFFE53935)); //红色（预设）
      expect(theme.seedColor(), const Color(0xFFE53935));
      await theme.setPresetSeed(const Color(0xFF123456)); //非预设，忽略
      expect(theme.seedColor(), const Color(0xFFE53935));
    });
  });
}
