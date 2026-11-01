import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'pages/favorites_page.dart';
import 'pages/home_page.dart';
import 'pages/playlist_detail_page.dart';
import 'providers/library_provider.dart';
import 'providers/playlist_provider.dart';
import 'providers/theme_provider.dart';
import 'services/audio_playback_service.dart';
import 'services/playlist_service.dart';
import 'services/sleep_timer_service.dart';

/// App 根组件：全局 Provider + MaterialApp
///
/// 主题（v1.0）：theme（日间）+ darkTheme（夜间）+ themeMode（明暗模式，
/// 跟随系统由 MaterialApp 自动处理）；配色由 [ThemeProvider.buildTheme]
/// 按"亮/暗默认 + 用户自定义 + 推荐主题色"构建。
/// 背景图：启用时全局背景层（MaterialApp.builder 包 Stack：背景图 + 遮罩），
/// 页面 Scaffold 背景透明露出背景图。
/// 背景图加载（双保险）：ThemeProvider 启动/换图时解码为内存 ui.Image，
/// 背景层优先用 RawImage 直接显示（切页零延迟）；内存图尚未就绪时
/// 回退 Image.file（走 ImageCache，命中缓存同样瞬时）——绝不出现空白等待。
class MusicApp extends StatefulWidget {
  const MusicApp({
    super.key,
    this.theme,
    this.playlists,
    this.initialPage,
    this.pageObserver,
  });

  /// 预加载的主题实例（main() 中 load + 预解码后传入）；
  /// 为空时（测试/其它入口）内部自建并异步 load 兜底。
  final ThemeProvider? theme;

  /// 预加载的歌单实例（main() 中 load 后传入，同时已同步给
  /// [PlaylistService.updatePlaylists]）；
  /// 为空时（测试/其它入口）内部自建并异步 load 兜底。
  final PlaylistProvider? playlists;

  /// v1.0 第四阶段"默认停留页面"：上次停留页值
  /// （`favorites` / `playlist:<id>`；null = 进主页）。
  final String? initialPage;

  /// 停留页记录器（跟踪栈顶目标页）
  final NavigatorObserver? pageObserver;

  @override
  State<MusicApp> createState() => _MusicAppState();
}

class _MusicAppState extends State<MusicApp> {
  bool _initialPushed = false; //初始页只 push 一次

  /// 首帧后进入上次停留页（栈底保持主页，返回键可回主页）
  void _pushInitialPage(BuildContext context) {
    if (_initialPushed) return;
    _initialPushed = true;
    final page = widget.initialPage;
    if (page == null) return;
    final nav = Navigator.of(context);
    if (page == 'favorites') {
      nav.push(MaterialPageRoute(
        settings: const RouteSettings(name: 'favorites'),
        builder: (_) => const FavoritesPage(),
      ));
    } else if (page.startsWith('playlist:')) {
      final id = page.substring('playlist:'.length);
      nav.push(MaterialPageRoute(
        settings: RouteSettings(name: page),
        builder: (_) => PlaylistDetailPage(playlistId: id),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        //歌曲库状态
        ChangeNotifierProvider(create: (_) => LibraryProvider()),
        //歌单状态（v1.0 第三阶段：自定义歌单 CRUD + 持久化）
        ChangeNotifierProvider(
          create: (_) {
            final p = widget.playlists ?? PlaylistProvider();
            //未预加载入口兜底：异步恢复持久化（失败保持默认，不阻塞）
            if (widget.playlists == null) unawaited(p.load());
            return p;
          },
        ),
        //主题状态（v1.0：明暗 + 推荐色 + 自定义颜色 + 背景图）
        ChangeNotifierProvider(
          create: (_) {
            final t = widget.theme ?? ThemeProvider();
            //未预加载入口兜底：异步恢复持久化（失败保持默认，不阻塞）
            if (widget.theme == null) unawaited(t.load());
            return t;
          },
        ),
        //播放服务（全局单例，跨页面共享播放状态）
        ChangeNotifierProvider.value(value: AudioPlaybackService.instance),
        //播放队列服务（全局单例，队列/模式状态）
        ChangeNotifierProvider.value(value: PlaylistService.instance),
        //睡眠定时（v1.2）
        ChangeNotifierProvider.value(value: SleepTimerService.instance),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, theme, _) => MaterialApp(
          title: 'FangMusic',
          debugShowCheckedModeBanner: false,
          theme: theme.buildTheme(Brightness.light),
          darkTheme: theme.buildTheme(Brightness.dark),
          themeMode: theme.themeMode,
          //v1.0 第四阶段：停留页跟踪（NavigatorObserver 记录栈顶目标页）
          navigatorObservers: [if (widget.pageObserver != null) widget.pageObserver!],
          //全局背景层已移除（补充 17，方案 A）：背景改为**页面级**——
          //每个页面 Scaffold 之下挂 AppBackground（widgets/app_background.dart），
          //页面出现即带背景，切页零延迟；不再依赖全局单层的时序。
          //（同时为 v1.1"不同页面不同背景图"铺路：按页面取图即可）
          builder: (context, child) => child ?? const SizedBox(),
          //v1.0 第四阶段：默认停留页面——首帧后进入上次停留页（仅一次）
          home: Builder(
            builder: (context) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _pushInitialPage(context);
              });
              return const HomePage();
            },
          ),
        ),
      ),
    );
  }
}
