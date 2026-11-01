import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'providers/playlist_provider.dart';
import 'providers/theme_provider.dart';
import 'services/last_page_observer.dart';
import 'services/list_view_prefs_service.dart';
import 'services/music_audio_handler.dart';
import 'services/navigation_prefs.dart';
import 'services/playback_stats_service.dart';
import 'services/playlist_service.dart';

/// 入口
///
/// 启动顺序的坑（已踩过）：
/// - 后台播放初始化可能失败/卡住：必须异步执行 + 超时容错，不能阻塞 runApp
/// - 权限请求必须在界面完全就绪后执行（在 HomePage 首帧后），
///   过早调用会抛 "Unable to detect current Android Activity"
///
/// v1.0 启动优化（消除背景图延迟）：
/// - runApp **前**先 load() 恢复主题持久化配置（明暗/推荐色/自定义/背景图——
///   此前 load 从未被调用，主题设置重启后丢失，一并修复）；
/// - 再 await precacheBackgroundImage() 预解码背景图到内存，
///   **首帧即显示背景图**（不再"先默认背景、后加载出图"）。
///
/// v1.0 第三阶段：歌单数据同样在 runApp 前 load，并同步给
/// [PlaylistService.updatePlaylists]——这样播放队列服务初始化
/// （LibraryProvider.loadSongs → PlaylistService.init）时，
/// 若持久化播放源是某歌单，歌单数据已就绪（可正确重建歌单池）。
/// 停留页记录器（v1.0 第四阶段）：跟踪栈顶"主页/收藏/歌单页"，
/// 供应用退到后台/退出时持久化（模块级保持引用，防被 GC）
final LastPageObserver _pageObserver = LastPageObserver();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  //后台播放 + 媒体通知（audio_service，异步初始化，失败降级为普通前台播放）
  unawaited(_initAudioService());
  //v1.2：列表展示偏好 + 播放次数统计需在首次建列表前就绪
  await ListViewPrefsService.instance.load();
  await PlaybackStatsService.instance.load();
  //主题预加载：恢复持久化 + 预解码背景图（首帧带图；失败不阻塞启动）
  final theme = ThemeProvider();
  await theme.load();
  await theme.precacheBackgroundImages();
  //歌单预加载：恢复持久化 + 同步给播放队列服务（播放源是歌单时用）
  final playlists = PlaylistProvider();
  await playlists.load();
  PlaylistService.instance.updatePlaylists(playlists.playlists);
  //v1.0 第四阶段：默认停留页面——读开关（默认开）+ 上次停留页；
  //开关关闭则每次进主页（不传 initialPage）
  final stay = await NavigationPrefs.loadStayLastPage();
  final initialPage = stay ? await NavigationPrefs.loadLastPage() : null;
  //应用进入后台/被系统终止时：记录当前停留页（保留引用防 GC）
  AppLifecycleListener(
    onStateChange: (state) {
      if (state == AppLifecycleState.inactive ||
          state == AppLifecycleState.paused ||
          state == AppLifecycleState.detached) {
        NavigationPrefs.saveLastPage(_pageObserver.currentName);
      }
    },
  );
  runApp(MusicApp(
    theme: theme,
    playlists: playlists,
    initialPage: initialPage,
    pageObserver: _pageObserver,
  ));
}

/// 后台播放初始化（audio_service；容错：失败/超时不阻塞启动）
Future<void> _initAudioService() async {
  try {
    await AudioService.init(
      builder: () => MusicAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.example.fs_music.channel.audio',
        androidNotificationChannelName: '音乐播放',
        androidNotificationOngoing: true,
      ),
    ).timeout(const Duration(seconds: 8));
  } catch (e) {
    debugPrint('[main] 后台播放初始化失败，降级为普通播放：$e');
  }
}
