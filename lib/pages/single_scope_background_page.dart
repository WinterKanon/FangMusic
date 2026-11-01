import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../widgets/app_background.dart';
import '../widgets/page_background_section.dart';

/// 单个作用范围（页面 / 播放源 / 歌单）的背景设置页（v1.1-3）
///
/// 内部复用 [PageBackgroundSection]：预览 + 选图 + 遮罩 + 历史背景。
/// v1.1-3（用户 2026-10-29）：
/// - 回退上轮"背景透明"改动（用户将重新详述方案），恢复 settingsPages 背景；
/// - 保留顶部"明暗模式"（日间 / 夜间 / 跟随系统，与主题颜色页同款），
///   切换后预览与遮罩滑块实时反映对应明暗下的效果。
class SingleScopeBackgroundPage extends StatefulWidget {
  const SingleScopeBackgroundPage({
    super.key,
    required this.scopeKey,
    required this.title,
  });

  /// 作用范围 Key（页面 Key / queue:xx / pl:歌单id）
  final String scopeKey;

  /// 页面标题
  final String title;

  @override
  State<SingleScopeBackgroundPage> createState() =>
      _SingleScopeBackgroundPageState();
}

class _SingleScopeBackgroundPageState extends State<SingleScopeBackgroundPage> {
  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    return Stack(
      children: [
        const AppBackground(pageKey: 'settingsPages'),
        Scaffold(
      appBar: AppBar(title: Text(widget.title), centerTitle: true),
      body: Column(
        children: [
          //明暗模式（v1.1-3）：切换全局日/夜/跟随系统，
          //预览与遮罩滑块随之变化，便于直观看到日夜效果
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('明暗模式'),
                ),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode),
                        label: Text('日间')),
                    ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode),
                        label: Text('夜间')),
                    ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.brightness_auto),
                        label: Text('跟随系统')),
                  ],
                  selected: {theme.themeMode},
                  onSelectionChanged: (s) => theme.setThemeMode(s.first),
                ),
              ],
            ),
          ),
          Expanded(
            child: PageBackgroundSection(
              scopeKey: widget.scopeKey,
              title: widget.title,
            ),
          ),
        ],
      ),
        ),
      ],
    );
  }
}
