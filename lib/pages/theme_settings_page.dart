import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/status_colors.dart';
import '../models/theme_palette.dart';
import '../providers/theme_provider.dart';
import '../widgets/app_background.dart';
import '../widgets/preset_color_picker.dart';

/// 主题设置详情页（设置 → 主题）
///
/// 1. **明暗模式**：日间 / 夜间 / 跟随系统
/// 2. **系统推荐主题色**：红/橙/蓝/绿/黄/紫/粉色块
/// 3. **自定义颜色**：12 项区域颜色（点击弹色块选择，可单独恢复默认）
class ThemeSettingsPage extends StatelessWidget {
  const ThemeSettingsPage({super.key});

  /// 各区域的中文名
  static const Map<PaletteItem, String> itemLabels = {
    PaletteItem.background: '页面主背景',
    PaletteItem.surface: '列表项背景',
    PaletteItem.textPrimary: '主文字',
    PaletteItem.textSecondary: '次文字',
    PaletteItem.accent: '主题色',
    PaletteItem.icon: '通用图标（未单独设置的图标兜底）',
    PaletteItem.iconSearch: '搜索图标',
    PaletteItem.iconPrevious: '上一首图标',
    PaletteItem.iconNext: '下一首图标',
    PaletteItem.iconPlayPause: '播放/暂停图标',
    PaletteItem.iconMode: '播放模式图标',
    PaletteItem.iconQueue: '播放队列/排序图标',
    PaletteItem.iconMore: '更多操作图标',
    PaletteItem.iconSettings: '设置图标',
    PaletteItem.iconAdd: '添加图标',
    PaletteItem.favoriteStar: '收藏星标',
    PaletteItem.favoriteRed: '收藏红',
    PaletteItem.currentHighlight: '当前歌高亮',
    PaletteItem.queueNext: '播放队列下一首（队列中"下一首"标记）',
    PaletteItem.appBar: 'AppBar 背景（页面顶部栏）',
    PaletteItem.bottomBar: '底部播放栏背景（最下方播放条）',
    PaletteItem.drawer: '抽屉背景（左侧滑出菜单）',
    PaletteItem.dialog: '弹窗背景（对话框/底部弹窗）',
    PaletteItem.snackbarBg: '提示背景（底部提示条 SnackBar）',
    PaletteItem.snackbarText: '提示文字（底部提示条 SnackBar 文字）',
    PaletteItem.divider: '分割线（列表之间的分隔线）',
    PaletteItem.locateButtonBg: '悬浮定位按钮背景（主页/收藏/歌单页的定位按钮）',
    PaletteItem.locateButtonText: '悬浮定位按钮文字（定位按钮上的图标）',
    PaletteItem.jsonSearchBg: 'JSON 查找背景（JSON 页搜索弹窗）',
    PaletteItem.jsonSearchText: 'JSON 查找文字（JSON 页搜索弹窗文字）',
    PaletteItem.jsonHighlight1Bg: 'JSON 一级高亮关键词背景（JSON 页查找）',
    PaletteItem.jsonHighlight1Text: 'JSON 一级高亮关键词文字（JSON 页查找）',
    PaletteItem.jsonHighlight2Bg: 'JSON 二级高亮关键词背景（JSON 页查找）',
    PaletteItem.jsonHighlight2Text: 'JSON 二级高亮关键词文字（JSON 页查找）',
  };

  /// 分组展示顺序（图标区展开为逐项可自定义）
  static const List<({String title, List<PaletteItem> items})> _groups = [
    (
      title: '背景与文字',
      items: [
        PaletteItem.background,
        PaletteItem.surface,
        PaletteItem.textPrimary,
        PaletteItem.textSecondary,
      ],
    ),
    (
      title: '强调与图标',
      items: [
        PaletteItem.accent,
        PaletteItem.icon,
        PaletteItem.locateButtonBg,
        PaletteItem.locateButtonText,
        PaletteItem.iconSearch,
        PaletteItem.iconPrevious,
        PaletteItem.iconNext,
        PaletteItem.iconPlayPause,
        PaletteItem.iconMode,
        PaletteItem.iconQueue,
        PaletteItem.iconMore,
        PaletteItem.iconSettings,
        PaletteItem.iconAdd,
        //JSON 高亮关键词（v1.1-3，用户 2026-10-29：位于"添加图标"之下）
        PaletteItem.jsonHighlight1Bg,
        PaletteItem.jsonHighlight1Text,
        PaletteItem.jsonHighlight2Bg,
        PaletteItem.jsonHighlight2Text,
      ],
    ),
    (
      title: '状态色',
      items: [
        PaletteItem.favoriteStar,
        PaletteItem.favoriteRed,
        PaletteItem.currentHighlight,
        PaletteItem.queueNext,
      ],
    ),
    (
      title: '栏与弹窗',
      items: [
        PaletteItem.appBar,
        PaletteItem.bottomBar,
        PaletteItem.drawer,
        PaletteItem.dialog,
        PaletteItem.snackbarBg,
        PaletteItem.snackbarText,
        PaletteItem.jsonSearchBg,
        PaletteItem.jsonSearchText,
        PaletteItem.divider,
      ],
    ),
  ];

  /// 选色器色板：Material 原色 + 黑白灰（每个色块下方带颜色名）
  static final List<({Color color, String name})> _paletteColors = [
    (color: Colors.red, name: '红'),
    (color: Colors.pink, name: '粉'),
    (color: Colors.purple, name: '紫'),
    (color: Colors.deepPurple, name: '深紫'),
    (color: Colors.indigo, name: '靛'),
    (color: Colors.blue, name: '蓝'),
    (color: Colors.lightBlue, name: '天蓝'),
    (color: Colors.cyan, name: '青'),
    (color: Colors.teal, name: '青绿'),
    (color: Colors.green, name: '绿'),
    (color: Colors.lightGreen, name: '浅绿'),
    (color: Colors.lime, name: '黄绿'),
    (color: Colors.yellow, name: '黄'),
    (color: Colors.amber, name: '琥珀'),
    (color: Colors.orange, name: '橙'),
    (color: Colors.deepOrange, name: '深橙'),
    (color: Colors.brown, name: '棕'),
    (color: Colors.grey, name: '灰'),
    (color: Colors.blueGrey, name: '蓝灰'),
    (color: Colors.black, name: '黑'),
    (color: const Color(0xFF212121), name: '炭黑'),
    (color: const Color(0xFF424242), name: '深灰'),
    (color: const Color(0xFFBDBDBD), name: '浅灰'),
    (color: const Color(0xFFE0E0E0), name: '银白'),
    (color: Colors.white, name: '白'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    return Stack(
      children: [
        //页面级背景（补充 17）：背景 + 遮罩在 Scaffold 之下，页面出现即带背景
        const AppBackground(pageKey: ThemePalette.pageKeySettingsPages),
        Scaffold(
      appBar: AppBar(title: const Text('主题颜色'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
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
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('系统推荐主题色（点击色系展开具体颜色）'),
          ),
          //推荐主题色：默认（经典）选项 + 11 色系两级选择
          PresetColorPicker(
            selected: theme.presetSeed,
            defaultSelected: theme.isDefaultPreset,
            onSelect: (c) => theme.setPresetSeed(c),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('自定义颜色（点击色块修改，可单独恢复）'),
          ),
          //分组渲染（组间用分割线分区，减少密集感）：
          //背景与文字 / 强调与图标（图标逐项可自定义）/ 状态色 / 栏与弹窗
          for (final group in _groups) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 2),
              child: Text(
                group.title,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            for (final item in group.items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(itemLabels[item] ?? item.name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () => _showColorPicker(context, theme, item),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: _currentColor(context, theme, item),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Theme.of(context).colorScheme.outline),
                        ),
                      ),
                    ),
                    IconButton(
                      iconSize: 18,
                      tooltip: '恢复默认',
                      icon: const Icon(Icons.refresh),
                      onPressed: theme.palette.colorOf(item) == null
                          ? null
                          : () => theme.clearColor(item),
                    ),
                  ],
                ),
              ),
            const Divider(),
          ],
          const SizedBox(height: 8),
          //v1.0 第四阶段：一键恢复主题页全部默认设置（明暗模式/主题色/
          //全部自定义颜色/各遮罩浓度；背景图片路径不清除）
          OutlinedButton.icon(
            icon: const Icon(Icons.restore),
            label: const Text('恢复默认设置'),
            onPressed: () => _confirmReset(context, theme),
          ),
        ],
      ),
      ),
    ],
    );
  }

  /// 取当前实际颜色（自定义 ?? 明暗默认）
  Color _currentColor(BuildContext context, ThemeProvider theme, PaletteItem item) {
    final custom = theme.palette.colorOf(item);
    if (custom != null) return Color(custom);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (item) {
      case PaletteItem.background:
        return isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5);
      case PaletteItem.surface:
        return isDark ? const Color(0xFF1E1E1E) : Colors.white;
      case PaletteItem.textPrimary:
        return isDark ? Colors.white : const Color(0xFF000000);
      case PaletteItem.textSecondary:
        return isDark ? Colors.white70 : Colors.black54;
      case PaletteItem.accent:
        return theme.seedColor(isDark);
      //图标类：具体图标项未设置时显示"通用图标"色（可回落明暗默认）
      case PaletteItem.icon:
      case PaletteItem.iconSearch:
      case PaletteItem.iconPrevious:
      case PaletteItem.iconNext:
      case PaletteItem.iconPlayPause:
      case PaletteItem.iconMode:
      case PaletteItem.iconQueue:
      case PaletteItem.iconMore:
      case PaletteItem.iconSettings:
      case PaletteItem.iconAdd:
        final v = theme.palette.iconColorOf(item);
        if (v != null) return Color(v);
        return isDark ? Colors.white70 : Colors.black54;
      //悬浮定位按钮（默认经典模式：日间黑/夜间白 底，图标相反色；
      //非默认主题色：强调色底 + 亮度对比色）——与 ThemeProvider 一致
      case PaletteItem.locateButtonBg:
        return theme.locateButtonBackground(isDark);
      case PaletteItem.locateButtonText:
        return theme.locateButtonText(isDark);
      //JSON 高亮关键词（v1.1-3，用户 2026-10-29 拍板：默认背景 = 主题色、
      //文字 = 主题色反色；一级/二级默认相同，可分别自定义）
      case PaletteItem.jsonHighlight1Bg:
      case PaletteItem.jsonHighlight2Bg:
        return theme.seedColor(isDark);
      case PaletteItem.jsonHighlight1Text:
      case PaletteItem.jsonHighlight2Text:
        return theme.seedColor(isDark).computeLuminance() > 0.5
            ? Colors.black
            : Colors.white;
      //JSON 查找弹窗（默认：背景 = 日白/夜黑，文字 = 主题色，同提示条语义）
      case PaletteItem.jsonSearchBg:
        return isDark ? Colors.black : Colors.white;
      case PaletteItem.jsonSearchText:
        return theme.isDefaultPreset
            ? ThemeProvider.kDefaultHighlightBlue
            : theme.seedColor(isDark);
      //状态色（默认：星标 amber、收藏红红、
      //当前歌高亮——默认模式用经典蓝，否则用主题色互补色）
      case PaletteItem.favoriteStar:
        return const Color(0xFFFFC107);
      case PaletteItem.favoriteRed:
        return const Color(0xFFF44336);
      case PaletteItem.currentHighlight:
        return theme.isDefaultPreset
            ? ThemeProvider.kDefaultHighlightBlue
            : StatusColors.complementOf(theme.seedColor(isDark));
      //播放队列"下一首"标记：默认 = 主题色
      case PaletteItem.queueNext:
        return theme.seedColor(isDark);
      case PaletteItem.appBar:
      case PaletteItem.bottomBar:
      case PaletteItem.drawer:
        return isDark ? const Color(0xFF1F1F1F) : Colors.white;
      case PaletteItem.dialog:
        return isDark ? const Color(0xFF2C2C2C) : Colors.white;
      //提示条默认配色：背景 = 日间白 / 夜间黑；文字 = 主题色
      //（默认经典模式 = 经典蓝，其余 = 主题色，与 buildTheme 一致）
      case PaletteItem.snackbarBg:
        return isDark ? Colors.black : Colors.white;
      case PaletteItem.snackbarText:
        return theme.isDefaultPreset
            ? ThemeProvider.kDefaultHighlightBlue
            : theme.seedColor(isDark);
      case PaletteItem.divider:
        return isDark ? Colors.white12 : Colors.black12;
    }
  }

  /// 确认后一键恢复主题页全部默认设置（防误触确认弹窗）
  Future<void> _confirmReset(BuildContext context, ThemeProvider theme) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复默认设置'),
        content: const Text('将恢复"主题颜色"页的全部默认设置：\n'
            '· 明暗模式 → 跟随系统\n'
            '· 系统推荐主题色 → 默认（经典紫）\n'
            '· 全部自定义颜色 → 清除\n\n'
            '背景图片页的遮罩浓度与背景图片路径保持不变。确定恢复吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await theme.resetAllThemeSettings();
    }
  }

  /// 弹出色块选择器（BottomSheet）：
  /// 1. **系统推荐色系**：全部推荐色（色值/色名，与"系统推荐主题色"一致）
  /// 2. **常用颜色**：预设色网格，每个色块下方带颜色名
  /// 3. **自定义调色**：色相/饱和度/亮度三滑杆自由调色 + 实时预览，确定后使用
  /// isScrollControlled = 固定高度弹窗 + 右侧滚动指示条（内容长时可滑动查看全部）
  Future<void> _showColorPicker(
      BuildContext context, ThemeProvider theme, PaletteItem item) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ColorPickerSheet(
        title: '选择${itemLabels[item] ?? item.name}颜色',
        onPick: (c) => theme.setColor(item, c),
        //v1.0 第四阶段：把"系统推荐主题色"全部色系并入弹窗（相同色值
        //去重、推荐色名优先；常用色补充未覆盖的颜色）
        presets: _mergedPresetColors(),
      ),
    );
  }

  /// 推荐色系 + 常用色合并（按色值去重，推荐色系优先展示）
  static List<({Color color, String name})> _mergedPresetColors() {
    final seen = <int>{};
    final merged = <({Color color, String name})>[];
    for (final g in ThemeProvider.presetGroups) {
      for (final c in g.colors) {
        if (seen.add(c.color.toARGB32())) merged.add(c);
      }
    }
    for (final c in _paletteColors) {
      if (seen.add(c.color.toARGB32())) merged.add(c);
    }
    return merged;
  }
}

/// 颜色选择弹窗（v1.0 第四阶段）：
/// 1. **系统推荐色系**（全部推荐色，带色名，与"系统推荐主题色"一致）
/// 2. **常用颜色**（预设色网格，带色名）
/// 3. **自定义调色**（色相/饱和度/亮度滑杆 + 实时预览）
/// 固定高度 + 右侧滚动指示条（内容超出时上滑查看全部）
class _ColorPickerSheet extends StatefulWidget {
  const _ColorPickerSheet({
    required this.title,
    required this.onPick,
    required this.presets,
  });

  final String title;

  /// 选中一个颜色时回调（预设色点击立即回调；调色盘点击"使用此颜色"回调）
  final ValueChanged<Color> onPick;

  /// 推荐色系 + 常用色合并后的颜色列表（色值/色名）
  final List<({Color color, String name})> presets;

  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  //自由调色盘 HSV 状态（默认紫色起始）
  double _hue = 260;
  double _saturation = 0.80;
  double _value = 1.0;

  //滚动控制器与指示条状态：内容超出弹窗高度时可滚动，
  //右侧细条提示当前滚动位置与可见比例
  final ScrollController _scrollController = ScrollController();
  double _viewRatio = 1.0; //可见比例（内容全显示 = 1，不显示指示条）
  double _offsetRatio = 0.0; //滚动偏移比例（0 顶 ~ 1 底）

  Color get _previewColor =>
      HSVColor.fromAHSV(1, _hue, _saturation, _value).toColor();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateIndicator);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateIndicator);
    _scrollController.dispose();
    super.dispose();
  }

  /// 根据滚动位置刷新指示条（内容不超屏时 _viewRatio = 1 → 隐藏）
  void _updateIndicator() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final content = pos.maxScrollExtent + pos.viewportDimension;
    setState(() {
      _viewRatio = content > 0
          ? (pos.viewportDimension / content).clamp(0.0, 1.0)
          : 1.0;
      _offsetRatio = pos.maxScrollExtent > 0
          ? (pos.pixels / pos.maxScrollExtent).clamp(0.0, 1.0)
          : 0.0;
    });
  }

  /// 单个色块（点击立即回调 + 色名标注）
  Widget _colorCell(BuildContext context, Color color, String name) {
    return GestureDetector(
      onTap: () {
        widget.onPick(color);
        Navigator.of(context).pop();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          const SizedBox(height: 3),
          Text(name, style: const TextStyle(fontSize: 10)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      //固定高度弹窗（约屏高 62%）：全部内容在一个滚动区内，右侧带指示条
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.62,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                widget.title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          //1. 全部可选颜色（推荐色系优先 + 常用色补充，已去重）
                          const Text(
                            '选择颜色（推荐色系 + 常用色）',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 12,
                            runSpacing: 16,
                            children: [
                              for (final c in widget.presets)
                                _colorCell(context, c.color, c.name),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Divider(),
                          const Text(
                            '自定义调色',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          //色相滑杆（0~360）
                          Row(
                            children: [
                              const SizedBox(width: 40, child: Text('色相')),
                              Expanded(
                                child: Slider(
                                  min: 0,
                                  max: 360,
                                  value: _hue,
                                  onChanged: (v) => setState(() => _hue = v),
                                ),
                              ),
                              SizedBox(
                                width: 40,
                                child: Text('${_hue.round()}°',
                                    textAlign: TextAlign.right),
                              ),
                            ],
                          ),
                          //饱和度滑杆（0~1）
                          Row(
                            children: [
                              const SizedBox(width: 40, child: Text('饱和度')),
                              Expanded(
                                child: Slider(
                                  min: 0,
                                  max: 1,
                                  value: _saturation,
                                  onChanged: (v) =>
                                      setState(() => _saturation = v),
                                ),
                              ),
                              SizedBox(
                                width: 40,
                                child: Text('${(_saturation * 100).round()}%',
                                    textAlign: TextAlign.right),
                              ),
                            ],
                          ),
                          //亮度滑杆（0~1）
                          Row(
                            children: [
                              const SizedBox(width: 40, child: Text('亮度')),
                              Expanded(
                                child: Slider(
                                  min: 0,
                                  max: 1,
                                  value: _value,
                                  onChanged: (v) => setState(() => _value = v),
                                ),
                              ),
                              SizedBox(
                                width: 40,
                                child: Text('${(_value * 100).round()}%',
                                    textAlign: TextAlign.right),
                              ),
                            ],
                          ),
                          //预览 + 确定
                          Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: _previewColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () {
                                    widget.onPick(_previewColor);
                                    Navigator.of(context).pop();
                                  },
                                  child: const Text('使用此颜色'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  //右侧滚动指示条（类似进度条：槽 + 当前位置块）
                  _buildScrollIndicator(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 右侧滚动指示条：内容超出弹窗高度时显示。
  /// 细条 = 当前可见区域大小（占整体比例），位置随滚动上下移动
  Widget _buildScrollIndicator(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        //内容不超屏（无需滚动）时不显示指示条
        if (_viewRatio >= 1.0 || constraints.maxHeight <= 0) {
          return const SizedBox(width: 10);
        }
        final thumbHeight = constraints.maxHeight * _viewRatio;
        final top = (constraints.maxHeight - thumbHeight) * _offsetRatio;
        return Container(
          width: 10,
          margin: const EdgeInsets.symmetric(vertical: 12),
          child: Stack(
            children: [
              //槽：整条淡色背景
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              //当前位置块：高亮色（强调色）
              Positioned(
                top: top,
                left: 0,
                right: 0,
                height: thumbHeight.clamp(12.0, double.infinity),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
