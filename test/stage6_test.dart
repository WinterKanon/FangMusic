import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fs_music_app/models/play_mode.dart';
import 'package:provider/provider.dart';
import 'package:fs_music_app/pages/json_data_page.dart';
import 'package:fs_music_app/providers/theme_provider.dart';
import 'package:fs_music_app/services/playlist_service.dart';
import 'package:fs_music_app/services/storage_service.dart';

/// 阶段6 测试：
/// - StorageService 原始 JSON 读取在无平台通道时返回 null（不崩溃、不挂起）
/// - JSON 调试页空态 / 内容态（reader 注入，绕开测试环境文件 IO）
/// - 播放队列服务在空库下的边界行为（不崩溃、任务为空）
void main() {
  group('StorageService 原始 JSON 读取（无平台通道）', () {
    test('readSongsRaw / readPlayTasksRaw 返回 null，不抛异常', () async {
      expect(await StorageService.readSongsRaw(), isNull);
      expect(await StorageService.readPlayTasksRaw(), isNull);
    });
  });

  group('JSON 调试页（JsonDataPage）', () {
    testWidgets('文件不存在：两个 Tab 均显示空态', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: JsonDataPage(
            songsReader: () async => null,
            tasksReader: () async => null,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('文件尚未创建'), findsOneWidget);

      //切换"播放队列"Tab，同样显示空态
      await tester.tap(find.text('播放队列'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('文件尚未创建'), findsOneWidget);
      expect(find.textContaining('还没有生成播放队列'), findsOneWidget);
    });

    testWidgets('文件存在：显示原始 JSON 文本', (tester) async {
      const raw = '{"songs":[{"name":"demo","weight":100.0}]}';
      await tester.pumpWidget(
        MaterialApp(
          //v1.1-3：高亮配色依赖 ThemeProvider，测试需包裹（生产全局必有）
          home: ChangeNotifierProvider<ThemeProvider>(
            create: (_) => ThemeProvider(),
            child: JsonDataPage(
              songsReader: () async => raw,
              tasksReader: () async => null,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text(raw), findsOneWidget);
    });
  });

  group('空库边界（PlaylistService）', () {
    test('空库 init：队列为空、currentIndex=-1，不崩溃', () async {
      PlaylistService.instance.resetForTest();
      await PlaylistService.instance.init([]);
      expect(PlaylistService.instance.tasks, isEmpty);
      expect(PlaylistService.instance.length, 0);
      expect(PlaylistService.instance.currentIndex, -1);
    });

    test('空库 nextTask/previousTask：返回 null，不崩溃', () {
      PlaylistService.instance.resetForTest();
      expect(PlaylistService.instance.nextTask(), isNull);
      expect(PlaylistService.instance.previousTask(), isNull);
    });

    test('空库切模式：不崩溃，队列仍为空', () async {
      PlaylistService.instance.resetForTest();
      await PlaylistService.instance.setMode(PlayMode.realRandom);
      expect(PlaylistService.instance.tasks, isEmpty);
    });

    test('空库 addNextSong：插入一条任务，不崩溃', () {
      PlaylistService.instance.resetForTest();
      PlaylistService.instance.addNextSong('/nonexistent/song.mp3');
      expect(PlaylistService.instance.length, 1);
      expect(PlaylistService.instance.tasks.first.isNextSong, isTrue);
    });
  });
}
