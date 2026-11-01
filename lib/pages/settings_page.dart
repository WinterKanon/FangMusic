import 'package:flutter/material.dart';

import '../models/theme_palette.dart';
import '../services/navigation_prefs.dart';
import '../widgets/app_background.dart';
import 'background_settings_page.dart';
import 'json_data_page.dart';
import 'music_folders_page.dart';
import 'theme_settings_page.dart';
import 'weight_settings_page.dart';

/// 设置页（一级入口，v1.0）
///
/// 按类别列出入口，点击后进入对应详情页：
/// - **主题**：明暗模式 + 系统推荐主题色 + 12 项自定义颜色
/// - **背景图片**：相册/文件管理器选图、裁剪、透明度调节、历史背景图管理
/// - **权重调节**：v1.0 第二阶段开放（事件调权数值、权重范围、重置权重）
/// - **调试**：JSON 数据内容（v1.0 第四阶段从抽屉移至此处）
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  /// "默认停留页面"开关（v1.0 第四阶段；默认开）
  bool _stayLastPage = true;

  @override
  void initState() {
    super.initState();
    NavigationPrefs.loadStayLastPage().then((v) {
      if (mounted && v != _stayLastPage) setState(() => _stayLastPage = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        //页面级背景（补充 17）：背景 + 遮罩在 Scaffold 之下，页面出现即带背景
        const AppBackground(pageKey: ThemePalette.pageKeySettingsPages),
        Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: true),
      body: ListView(
        children: [
          const _SectionHeader('外观'),
          ListTile(
            leading: const Icon(Icons.palette),
            title: const Text('主题颜色'),
            subtitle: const Text('明暗模式、推荐主题色、自定义颜色'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ThemeSettingsPage()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.wallpaper),
            title: const Text('背景图片与遮罩浓度'),
            subtitle: const Text('选图、裁剪、透明度、历史背景图'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BackgroundSettingsPage()),
            ),
          ),
          const Divider(),
          const _SectionHeader('播放'),
          //v1.0 第四阶段："默认停留页面"开关（主 + 副说明文案）
          SwitchListTile(
            secondary: const Icon(Icons.flag),
            title: const Text('默认停留页面'),
            subtitle: const Text('每次打开FangMusic时打开上次退出FangMusic停留的页面'),
            value: _stayLastPage,
            onChanged: (v) {
              setState(() => _stayLastPage = v);
              NavigationPrefs.saveStayLastPage(v);
            },
          ),
          ListTile(
            leading: const Icon(Icons.folder_copy_outlined),
            title: const Text('所选文件夹管理'),
            subtitle: const Text('查看 / 移除已选择的音乐文件夹（不删除文件）'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MusicFoldersPage()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.scale),
            title: const Text('权重调节'),
            subtitle: const Text('事件调权数值、单曲权重、权重范围'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WeightSettingsPage()),
            ),
          ),
          const Divider(),
          //调试（v1.0 第四阶段：JSON 入口从抽屉移至设置页，
          //正常用户不需要用到，独立分区避免干扰常用入口）
          const _SectionHeader('调试'),
          ListTile(
            leading: const Icon(Icons.description),
            title: const Text('JSON 数据内容'),
            subtitle: const Text('查看歌曲库 / 歌单库 / 原始 JSON'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const JsonDataPage()),
            ),
          ),
        ],
      ),
      ),
    ],
    );
  }
}

/// 分区小标题
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
