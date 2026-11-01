import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_icon_colors.dart';
import '../models/status_colors.dart';
import '../models/theme_palette.dart';
import '../services/storage_service.dart';

/// 推荐主题色系（v1.0：色系 → 具体色两级选择）
///
/// 每种色系含 5~10 种常见颜色；[name] 为色系名（如"红色系"），
/// 每个具体色带自己的中文名（如"深红""血红"）。
class ThemePresetGroup {
  const ThemePresetGroup({required this.name, required this.colors});

  /// 色系名（如"红色系"）
  final String name;

  /// 该色系下的具体色（色值 + 色名）
  final List<({Color color, String name})> colors;
}

/// 主题状态管理（v1.0 主题定制）
///
/// 三个维度：
/// 1. **明暗模式**：日间 / 夜间 / 跟随系统（默认跟随系统，key `theme_mode`）
/// 2. **系统推荐主题色**：13 色系两级选择（红色系/橙色系/…/白色系，
///    每系 5~10 色，点击色系展开小弹窗选具体色；key `theme_seed_color`）；
///    推荐色同时驱动**文字与图标默认色**（可被自定义覆盖），
///    强调色用 M3 标准色调
/// 3. **自定义颜色 + 背景图**：区域颜色（ThemePalette，key `theme_palette` 存 JSON）
///
/// [buildTheme] 用"亮/暗默认色 + 用户覆盖"构建 ThemeData，
/// 由 app.dart 的 MaterialApp（theme/darkTheme/themeMode）消费。
class ThemeProvider extends ChangeNotifier {
  static const _modeKey = 'theme_mode';
  static const _seedKey = 'theme_seed_color';
  static const _defaultKey = 'theme_default_preset';

  /// "默认"选项的哨兵色值（经典模式：日间黑字/夜间白字，不随主题色）。
  /// 黑色系已移除，纯黑不在 presets 中，无冲突。
  static const Color kDefaultPresetColor = Color(0xFF000000);

  /// 默认模式下"当前播放歌曲高亮"的颜色（经典蓝，可自定义覆盖）
  static const Color kDefaultHighlightBlue = Color(0xFF2196F3);

  /// 系统推荐主题色（按色系分组，每种 5~7 色；默认紫 = 紫色系"紫"）。
  /// 黑色系/白色系已移除（日间/夜间模式下使用有逻辑瑕疵，用户决定）。
  static const List<ThemePresetGroup> presetGroups = [
    ThemePresetGroup(
      name: '红色系',
      colors: [
        (color: Color(0xFF8B0000), name: '血红'),
        (color: Color(0xFFB71C1C), name: '深红'),
        (color: Color(0xFFE53935), name: '大红'),
        (color: Color(0xFFFF5252), name: '朱红'),
        (color: Color(0xFFE91E63), name: '玫红'),
        (color: Color(0xFFD50000), name: '亮红'),
        (color: Color(0xFFFF80AB), name: '淡粉'),
      ],
    ),
    ThemePresetGroup(
      name: '橙色系',
      colors: [
        (color: Color(0xFFFF5722), name: '橙红'),
        (color: Color(0xFFF57C00), name: '深橙'),
        (color: Color(0xFFFB8C00), name: '橙'),
        (color: Color(0xFFFFA000), name: '橘黄'),
        (color: Color(0xFFFFB74D), name: '杏橙'),
        (color: Color(0xFFFFCC80), name: '浅橙'),
      ],
    ),
    ThemePresetGroup(
      name: '黄色系',
      colors: [
        (color: Color(0xFFFFC107), name: '金黄'),
        (color: Color(0xFFF9A825), name: '深黄'),
        (color: Color(0xFFFDD835), name: '黄'),
        (color: Color(0xFFFFEE58), name: '柠檬黄'),
        (color: Color(0xFFFFF59D), name: '米黄'),
      ],
    ),
    ThemePresetGroup(
      name: '绿色系',
      colors: [
        (color: Color(0xFF2E7D32), name: '深绿'),
        (color: Color(0xFF388E3C), name: '森林绿'),
        (color: Color(0xFF43A047), name: '绿'),
        (color: Color(0xFF66BB6A), name: '苹果绿'),
        (color: Color(0xFF00E676), name: '青绿'),
        (color: Color(0xFF4DB6AC), name: '薄荷绿'),
      ],
    ),
    ThemePresetGroup(
      name: '青色系',
      colors: [
        (color: Color(0xFF00838F), name: '深青'),
        (color: Color(0xFF009688), name: '青'),
        (color: Color(0xFF00ACC1), name: '亮青'),
        (color: Color(0xFF26C6DA), name: '青蓝'),
        (color: Color(0xFF4DD0E1), name: '浅青'),
      ],
    ),
    ThemePresetGroup(
      name: '蓝色系',
      colors: [
        (color: Color(0xFF0D47A1), name: '深蓝'),
        (color: Color(0xFF1565C0), name: '宝蓝'),
        (color: Color(0xFF1E88E5), name: '蓝'),
        (color: Color(0xFF42A5F5), name: '天蓝'),
        (color: Color(0xFF29B6F6), name: '亮蓝'),
        (color: Color(0xFF90CAF9), name: '浅蓝'),
      ],
    ),
    ThemePresetGroup(
      name: '紫色系',
      colors: [
        (color: Color(0xFF4A148C), name: '深紫'),
        (color: Color(0xFF6A1B9A), name: '葡萄紫'),
        (color: Color(0xFF7C4DFF), name: '紫'),
        (color: Color(0xFFB388FF), name: '亮紫'),
        (color: Color(0xFFCE93D8), name: '薰衣草'),
        (color: Color(0xFFE1BEE7), name: '浅紫'),
      ],
    ),
    ThemePresetGroup(
      name: '粉色系',
      colors: [
        (color: Color(0xFF880E4F), name: '深粉'),
        (color: Color(0xFFD81B60), name: '粉'),
        (color: Color(0xFFFF4081), name: '亮粉'),
        (color: Color(0xFFF48FB1), name: '淡粉'),
        (color: Color(0xFFF8BBD0), name: '樱花粉'),
      ],
    ),
    ThemePresetGroup(
      name: '棕色系',
      colors: [
        (color: Color(0xFF4E342E), name: '深棕'),
        (color: Color(0xFF795548), name: '棕'),
        (color: Color(0xFF8D6E63), name: '浅棕'),
        (color: Color(0xFFA1887F), name: '黄棕'),
        (color: Color(0xFFBCAAA4), name: '卡其'),
      ],
    ),
    ThemePresetGroup(
      name: '靛蓝系',
      colors: [
        (color: Color(0xFF1A237E), name: '深靛'),
        (color: Color(0xFF3949AB), name: '靛'),
        (color: Color(0xFF5C6BC0), name: '浅靛'),
        (color: Color(0xFF7986CB), name: '亮靛'),
        (color: Color(0xFF9FA8DA), name: '淡靛'),
      ],
    ),
    ThemePresetGroup(
      name: '蓝灰系',
      colors: [
        (color: Color(0xFF37474F), name: '深蓝灰'),
        (color: Color(0xFF607D8B), name: '蓝灰'),
        (color: Color(0xFF90A4AE), name: '浅蓝灰'),
        (color: Color(0xFFB0BEC5), name: '冷灰'),
        (color: Color(0xFFCFD8DC), name: '烟灰'),
      ],
    ),
  ];

  /// 全部推荐色（扁平列表，setPresetSeed 校验用）
  static final List<Color> presets = [
    for (final g in presetGroups) ...g.colors.map((c) => c.color),
  ];

  /// 各推荐色的中文名（按 ARGB int 查色名）
  static final Map<int, String> presetNames = {
    for (final g in presetGroups)
      for (final c in g.colors) c.color.toARGB32(): c.name,
  };

  ThemeMode _themeMode = ThemeMode.system;
  Color _presetSeed = const Color(0xFF7C4DFF);
  bool _defaultPreset = false;
  final ThemePalette _palette = ThemePalette();
  bool _loaded = false;

  /// 明暗模式（默认跟随系统）
  ThemeMode get themeMode => _themeMode;

  /// 系统推荐主题色（palette.accent 自定义时优先）
  Color get presetSeed => _presetSeed;

  /// 是否处于"默认"（经典）模式：日间黑字/夜间白字，不随主题色驱动。
  /// 当前歌高亮用默认蓝（不用互补色，避免不明显）。
  bool get isDefaultPreset => _defaultPreset;

  /// 当前有效种子色（强调色/主题色）= 自定义强调色 ?? 推荐主题色。
  /// [isDark] 传入时，系统推荐主题色为"默认"时默认 = 日间白 / 夜间黑
  /// （v1.1-3，用户 2026-10-28 拍板；用户自定义强调色除外）；
  /// 不传时保持经典紫（兼容无明暗上下文的兜底）。
  Color seedColor([bool? isDark]) {
    final custom = _palette.colorOf(PaletteItem.accent);
    if (custom != null) return Color(custom);
    if (_defaultPreset) {
      if (isDark != null) return isDark ? Colors.black : Colors.white;
      return _presetSeed;
    }
    return _presetSeed;
  }

  /// 自定义调色板
  ThemePalette get palette => _palette;

  /// **悬浮定位按钮背景色**（v1.1-3，用户 2026-10-28 拍板）：
  /// - 自定义"悬浮定位按钮背景"时优先；
  /// - 默认：**与强调色（主题色）一致**（不再区分默认/非默认主题，
  ///   也不再使用遮罩浓度）。
  Color locateButtonBackground(bool isDark) {
    final custom = _palette.colorOf(PaletteItem.locateButtonBg);
    if (custom != null) return Color(custom);
    return seedColor(isDark);
  }

  /// **悬浮定位按钮文字/图标色**（v1.1-3，用户 2026-10-28 拍板）：
  /// - 自定义"悬浮定位按钮文字"时优先；
  /// - 默认：**强调色的反色**（按强调色亮度取对比色：亮底黑字 / 暗底白字）。
  Color locateButtonText(bool isDark) {
    final custom = _palette.colorOf(PaletteItem.locateButtonText);
    if (custom != null) return Color(custom);
    return seedColor(isDark).computeLuminance() > 0.5 ? Colors.black : Colors.white;
  }

  /// 一键恢复**"设置 → 主题颜色"页全部默认设置**（v1.0 第四阶段，
  /// 用户 2026-10-27 调整：只恢复主题颜色页，不涉及背景图片页）：
  /// 明暗模式 → 跟随系统；系统推荐主题色 → 默认（经典紫）；全部自定义
  /// 颜色 → 清除。背景图片页的遮罩浓度（背景/抽屉/定位按钮）**保持不变**。
  /// 背景图片路径也不清除（由背景图片页"移除当前背景"管理）。
  Future<void> resetAllThemeSettings() async {
    _themeMode = ThemeMode.system;
    _presetSeed = const Color(0xFF7C4DFF);
    _defaultPreset = false;
    _palette.resetColors();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_modeKey);
      await prefs.remove(_seedKey);
      await prefs.remove(_defaultKey);
      await prefs.remove(ThemePalette.prefKey);
    } catch (_) {}
  }

  bool get loaded => _loaded;

  //==================== 背景图内存缓存（v1.1-3：多路径多图） ====================
  // 缓存 Key = 背景图片**实际路径**：多页共用同一张图时共享同一份解码图，
  // 各页面（作用范围）通过 effectiveBackgroundPath 解析出自己的路径。

  /// 路径 → 已解码背景图（RawImage 直接渲染，切换页面零延迟）
  final Map<String, ui.Image> _backgroundImages = {};

  /// 某路径已解码的背景图（null = 未启用/未解码）
  ui.Image? backgroundImageForPath(String? path) =>
      path == null ? null : _backgroundImages[path];

  /// 预解码**全部生效背景图**（main 启动时调用：先 load() 再 await 本方法，
  /// 确保 app 首帧即显示背景图，切页零延迟）。幂等：已解码直接返回。
  Future<void> precacheBackgroundImages() async {
    final paths = <String>{
      //全局默认背景
      if (_palette.backgroundImagePath != null) _palette.backgroundImagePath!,
      //逐页配置
      for (final e in _palette.perPageBackgrounds.entries)
        if (e.value.imagePath != null) e.value.imagePath!,
      //逐歌单配置
      for (final e in _palette.perPlaylistBackgrounds.entries)
        if (e.value.imagePath != null) e.value.imagePath!,
    };
    for (final path in paths) {
      await _ensureBackgroundImageByPath(path);
    }
  }

  /// 公开：确保某路径背景图已解码（AppBackground 首次进入页面时触发，
  /// 解码完成后 notify → 该页背景出现）
  void ensureBackgroundImageByPath(String path) {
    unawaited(_ensureBackgroundImageByPath(path));
  }

  //按路径解码任务复用：同路径并发调用共享同一 Future
  final Map<String, Future<void>> _backgroundLoadTasks = {};
  final Map<String, String> _backgroundLoadPaths = {};

  /// 按路径异步解码到内存；**解码完成前保留旧图**（切图无缝，
  /// 不会闪回默认背景），完成后 notify（UI 瞬时切换）。
  Future<void> _ensureBackgroundImageByPath(String path) {
    if (_backgroundImages[path] != null) {
      return Future<void>.value();
    }
    if (_backgroundLoadTasks[path] != null &&
        _backgroundLoadPaths[path] == path) {
      return _backgroundLoadTasks[path]!;
    }
    final task = _decodeBackgroundImage(path);
    _backgroundLoadTasks[path] = task;
    _backgroundLoadPaths[path] = path;
    task.whenComplete(() {
      if (identical(_backgroundLoadTasks[path], task)) {
        _backgroundLoadTasks.remove(path);
        _backgroundLoadPaths.remove(path);
      }
    });
    return task;
  }

  Future<void> _decodeBackgroundImage(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final newImage = frame.image;
      final old = _backgroundImages[path];
      _backgroundImages[path] = newImage;
      _backgroundRetryCounts.remove(path);
      //旧图在新图就绪后才释放（避免切图瞬间闪回默认背景）
      if (old != null && !identical(old, newImage)) old.dispose();
      notifyListeners();
    } catch (e) {
      debugPrint('[theme] 背景图解码失败：$e');
      //真机瞬时失败（内存/IO）自动重试：1s 后重试，最多 3 次
      _scheduleBackgroundRetry(path);
    }
  }

  final Map<String, int> _backgroundRetryCounts = {};

  /// 解码失败后的延迟重试（最多 3 次）
  void _scheduleBackgroundRetry(String path) {
    final n = _backgroundRetryCounts[path] ?? 0;
    if (n >= 3) return;
    _backgroundRetryCounts[path] = n + 1;
    Future<void>.delayed(const Duration(seconds: 1), () {
      _ensureBackgroundImageByPath(path);
    });
  }

  //==================== 作用范围背景解析（v1.1-3） ====================

  /// 某作用范围 Key 的独立配置（null = 未单独设置）。
  /// Key：页面 Key / `queue:xx` 源级 Key / `pl:<歌单id>`。
  PageBackgroundConfig? backgroundConfigFor(String key) {
    if (key.startsWith(ThemePalette.playlistPrefix)) {
      return _palette.perPlaylistBackgrounds[
          key.substring(ThemePalette.playlistPrefix.length)];
    }
    return _palette.perPageBackgrounds[key];
  }

  /// 某作用范围**生效的背景路径**：精确配置 → 层级回退 → 全局默认。
  /// 回退链：`queue:xx` → `queue`（全部播放源）→ 全局；`pl:<id>` → 全局。
  String? effectiveBackgroundPath(String key) {
    final direct = backgroundConfigFor(key);
    if (direct?.imagePath != null) return direct!.imagePath;
    if (key.startsWith(ThemePalette.queueSourcePrefix)) {
      final queueAll = _palette.perPageBackgrounds[ThemePalette.pageKeyQueue];
      if (queueAll?.imagePath != null) return queueAll!.imagePath;
    }
    return _palette.backgroundImagePath;
  }

  /// 某作用范围**生效的遮罩浓度**（isDark 取夜间档；回退链同上）。
  /// 注意：仅调遮罩未选图的范围，图片回退全局、遮罩用本范围值。
  double effectiveBackgroundMask(String key, bool isDark) {
    final direct = backgroundConfigFor(key);
    if (direct != null) return isDark ? direct.maskNight : direct.maskDay;
    if (key.startsWith(ThemePalette.queueSourcePrefix)) {
      final queueAll = _palette.perPageBackgrounds[ThemePalette.pageKeyQueue];
      if (queueAll != null) {
        return isDark ? queueAll.maskNight : queueAll.maskDay;
      }
    }
    return isDark
        ? _palette.backgroundOverlayAlphaDark
        : _palette.backgroundOverlayAlphaLight;
  }

  //==================== 加载与持久化 ====================

  /// 从偏好加载全部主题状态；失败保持默认
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      //明暗模式
      final modeName = prefs.getString(_modeKey);
      if (modeName != null) {
        for (final m in ThemeMode.values) {
          if (m.name == modeName) {
            _themeMode = m;
            break;
          }
        }
      }
      //"默认"（经典）模式标记
      _defaultPreset = prefs.getBool(_defaultKey) ?? false;
      //推荐主题色
      final seed = prefs.getInt(_seedKey);
      if (seed != null && presets.contains(Color(seed))) {
        _presetSeed = Color(seed);
      }
      //自定义颜色 + 背景图 + **遮罩浓度**（夜间/日间分开恢复——
      //此前漏恢复遮罩字段，导致重启后日间/夜间遮罩都回默认值）
      final paletteRaw = prefs.getString(ThemePalette.prefKey);
      if (paletteRaw != null) {
        final loaded = ThemePalette.fromJson(paletteRaw);
        _palette.backgroundImagePath = loaded.backgroundImagePath;
        _palette.backgroundOverlayAlphaDark = loaded.backgroundOverlayAlphaDark;
        _palette.backgroundOverlayAlphaLight = loaded.backgroundOverlayAlphaLight;
        _palette.drawerOverlayAlphaDark = loaded.drawerOverlayAlphaDark;
        _palette.drawerOverlayAlphaLight = loaded.drawerOverlayAlphaLight;
        //悬浮定位按钮遮罩浓度（v1.0 曾漏加载 → 重启后浓度回默认，顺带修复）
        _palette.locateOverlayAlpha = loaded.locateOverlayAlpha;
        //逐页 / 逐歌单背景配置（v1.1-3）
        _palette.perPageBackgrounds
          ..clear()
          ..addAll(loaded.perPageBackgrounds);
        _palette.perPlaylistBackgrounds
          ..clear()
          ..addAll(loaded.perPlaylistBackgrounds);
        for (final item in PaletteItem.values) {
          final v = loaded.colorOf(item);
          if (v != null) _palette.setColor(item, v);
        }
      }
      //旧版本只有"图标"一项：迁移为所有具体图标项继承同色（用户可再逐个改）
      final genericIcon = _palette.colorOf(PaletteItem.icon);
      if (genericIcon != null) {
        for (final item in ThemePalette.specificIconItems) {
          if (_palette.colorOf(item) == null) {
            _palette.setColor(item, genericIcon);
          }
        }
      }
      _loaded = true;
    } catch (_) {
      //读取失败保持默认
    }
    notifyListeners();
    //启动时预解码全部生效背景图（全局 + 逐页 + 逐歌单），切页零延迟
    unawaited(precacheBackgroundImages());
  }

  /// 设置明暗模式并持久化
  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_modeKey, mode.name);
    } catch (_) {}
  }

  /// 选择系统推荐主题色并持久化；"默认"（经典）选项传 [kDefaultPresetColor]。
  /// 仅接受预设色或"默认"哨兵；无效颜色忽略。
  Future<void> setPresetSeed(Color color) async {
    final isDefault = color == kDefaultPresetColor;
    if (!isDefault && !presets.contains(color)) return;
    if (isDefault
        ? _defaultPreset
        : (!_defaultPreset && color == _presetSeed)) {
      return;
    }
    _defaultPreset = isDefault;
    if (!isDefault) _presetSeed = color;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_defaultKey, isDefault);
      if (isDefault) {
        await prefs.remove(_seedKey);
      } else {
        await prefs.setInt(_seedKey, color.toARGB32());
      }
    } catch (_) {}
  }

  /// 自定义某区域颜色并持久化
  Future<void> setColor(PaletteItem item, Color color) async {
    if (color.toARGB32() == _palette.colorOf(item)) return;
    _palette.setColor(item, color.toARGB32());
    notifyListeners();
    await _savePalette();
  }

  /// 清除某区域自定义（恢复明暗默认）并持久化
  Future<void> clearColor(PaletteItem item) async {
    _palette.clearColor(item);
    notifyListeners();
    await _savePalette();
  }

  /// 设置/清除**全局**背景图（null = 清除，全部页面回退默认背景）。
  /// v1.1-3：逐页/逐歌单覆盖见 [setPageBackgroundPath]。
  Future<void> setBackgroundImage(String? path) async {
    if (_palette.backgroundImagePath == path) return;
    _palette.backgroundImagePath = path;
    notifyListeners();
    //重新解码内存背景图（异步，完成后再次 notify）
    if (path != null) unawaited(_ensureBackgroundImageByPath(path));
    await _savePalette();
  }

  /// 设置某作用范围 Key 的背景图（null = 清除该范围配置 → 回退全局）。
  /// Key 生成：[ThemePalette.queueSourceKey]（播放队列源级）/
  /// [ThemePalette.playlistKey]（歌单）/ 页面 Key 常量。
  Future<void> setPageBackgroundPath(String key, String? path) async {
    if (key.startsWith(ThemePalette.playlistPrefix)) {
      final id = key.substring(ThemePalette.playlistPrefix.length);
      if (path == null) {
        _palette.perPlaylistBackgrounds.remove(id);
      } else {
        (_palette.perPlaylistBackgrounds[id] ??= PageBackgroundConfig())
            .imagePath = path;
      }
    } else {
      if (path == null) {
        _palette.perPageBackgrounds.remove(key);
      } else {
        (_palette.perPageBackgrounds[key] ??= PageBackgroundConfig())
            .imagePath = path;
      }
    }
    notifyListeners();
    if (path != null) unawaited(_ensureBackgroundImageByPath(path));
    await _savePalette();
  }

  /// 是否已有任意页面/歌单/播放源级的独立背景配置
  bool get hasPageBackgroundOverrides =>
      _palette.perPageBackgrounds.isNotEmpty ||
      _palette.perPlaylistBackgrounds.isNotEmpty;

  /// 清除**所有页面级自定义**（背景图 + 遮罩浓度），全部回退全局默认。
  /// 不影响全局背景图，也不删除历史背景图片（仍可复用）。
  Future<void> clearAllPageBackgrounds() async {
    if (!hasPageBackgroundOverrides) return;
    _palette.perPageBackgrounds.clear();
    _palette.perPlaylistBackgrounds.clear();
    notifyListeners();
    await _savePalette();
  }

  /// 调节某作用范围 Key 的遮罩浓度（日/夜分开；仅调遮罩未选图时，
  /// 图片回退全局、遮罩用本范围值）。
  Future<void> setPageMask(String key,
      {required bool isDark, required double alpha}) async {
    final PageBackgroundConfig config;
    if (key.startsWith(ThemePalette.playlistPrefix)) {
      config = _palette.perPlaylistBackgrounds.putIfAbsent(
          key.substring(ThemePalette.playlistPrefix.length),
          PageBackgroundConfig.new);
    } else {
      config = _palette.perPageBackgrounds
          .putIfAbsent(key, PageBackgroundConfig.new);
    }
    final v = alpha.clamp(0.0, 1.0);
    if (isDark) {
      if ((config.maskNight - v).abs() < 0.001) return;
      config.maskNight = v;
    } else {
      if ((config.maskDay - v).abs() < 0.001) return;
      config.maskDay = v;
    }
    notifyListeners();
    await _savePalette();
  }

  /// 调节**夜间**背景图遮罩不透明度（0.0 ~ 1.0，默认 0.30）
  Future<void> setBackgroundOverlayAlphaDark(double alpha) async {
    final v = alpha.clamp(0.0, 1.0);
    if ((_palette.backgroundOverlayAlphaDark - v).abs() < 0.001) return;
    _palette.backgroundOverlayAlphaDark = v;
    notifyListeners();
    await _savePalette();
  }

  /// 调节**日间**背景图遮罩不透明度（0.0 ~ 1.0，默认 0.0）
  Future<void> setBackgroundOverlayAlphaLight(double alpha) async {
    final v = alpha.clamp(0.0, 1.0);
    if ((_palette.backgroundOverlayAlphaLight - v).abs() < 0.001) return;
    _palette.backgroundOverlayAlphaLight = v;
    notifyListeners();
    await _savePalette();
  }

  /// 调节**夜间**抽屉栏遮罩浓度（0.0 全透明 ~ 1.0 全黑，默认 0.65）
  Future<void> setDrawerOverlayAlphaDark(double alpha) async {
    final v = alpha.clamp(0.0, 1.0);
    if ((_palette.drawerOverlayAlphaDark - v).abs() < 0.001) return;
    _palette.drawerOverlayAlphaDark = v;
    notifyListeners();
    await _savePalette();
  }

  /// 调节**日间**抽屉栏遮罩浓度（0.0 全透明 ~ 1.0 全白，默认 0.65）
  Future<void> setDrawerOverlayAlphaLight(double alpha) async {
    final v = alpha.clamp(0.0, 1.0);
    if ((_palette.drawerOverlayAlphaLight - v).abs() < 0.001) return;
    _palette.drawerOverlayAlphaLight = v;
    notifyListeners();
    await _savePalette();
  }

  Future<void> _savePalette() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(ThemePalette.prefKey, _palette.toJson());
    } catch (_) {}
  }

  //==================== 背景图导入与管理 ====================

  /// 从系统**相册/图库**选图（FileType.image）→ 裁剪 → 复制到 app 内 → 设为当前。
  /// 返回新背景图路径；取消/失败返回 null。
  Future<String?> importBackgroundFromGallery() {
    return _pickCropCopy(() => FilePicker.platform.pickFiles(
          type: FileType.image,
          //关闭 file_picker 的图片压缩：其压缩实现会把副本写到
          //内部存储/Pictures/（相册多出一张图），本 app 自己压缩到临时目录
          allowCompression: false,
        ));
  }

  /// 从**系统文件管理器**选一个图片文件（自定义扩展名过滤，类似选音乐文件夹）
  /// → 裁剪 → 复制到 app 内 → 设为当前。返回新背景图路径；取消/失败返回 null。
  Future<String?> importBackgroundFromFiles() {
    return _pickCropCopy(() => FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'],
        ));
  }

  /// 为某作用范围 Key 从**相册**选图 → 裁剪 → 复制 → 设为该范围背景
  Future<String?> importBackgroundForKeyFromGallery(String key) =>
      _pickCropCopy(
          () => FilePicker.platform.pickFiles(
                type: FileType.image,
                allowCompression: false, //避免 file_picker 在 Pictures 留副本
              ),
          targetKey: key);

  /// 为某作用范围 Key 从**文件管理器**选图 → 裁剪 → 复制 → 设为该范围背景
  Future<String?> importBackgroundForKeyFromFiles(String key) =>
      _pickCropCopy(
          () => FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: [
                  'jpg',
                  'jpeg',
                  'png',
                  'webp',
                  'gif',
                  'bmp'
                ],
              ),
          targetKey: key);

  /// 选图 → 裁剪 → 复制到背景图目录 → 设为当前背景。
  /// [targetKey] 为 null 时设为**全局**背景；否则设为该作用范围的独立背景。
  Future<String?> _pickCropCopy(
    Future<FilePickerResult?> Function() picker, {
    String? targetKey,
  }) async {
    try {
      final picked = await picker();
      if (picked == null || picked.files.isEmpty) return null;
      final sourcePath = picked.files.first.path;
      if (sourcePath == null) return null;

      //裁剪（用户可跳过；image_cropper 原生裁剪界面）
      var finalPath = await _cropImage(sourcePath) ?? sourcePath;

      //压缩降采样（最长边 1920 / JPEG 质量 85）：显著减小文件体积与
      //解码耗时，加快全局背景图加载；失败时回退原图
      finalPath = await _compressForBackground(finalPath);

      final newPath = await StorageService.copyToBackgroundDir(finalPath);
      if (newPath != null) {
        if (targetKey == null) {
          await setBackgroundImage(newPath);
        } else {
          await setPageBackgroundPath(targetKey, newPath);
        }
      }
      return newPath;
    } catch (e) {
      debugPrint('[theme] 导入背景图失败：$e');
      return null;
    }
  }

  /// 调用系统裁剪（image_cropper）；用户取消裁剪返回 null（用原图）。
  /// 限制输出尺寸（最长边 1920）避免超大图入库。
  Future<String?> _cropImage(String sourcePath) async {
    try {
      final cropped = await ImageCropper().cropImage(
        sourcePath: sourcePath,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 92,
        maxWidth: 1920,
        maxHeight: 1920,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: '裁剪图片',
            toolbarColor: const Color(0xFF1F1F1F),
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
            backgroundColor: const Color(0xFF121212),
          ),
          IOSUiSettings(
            title: '裁剪图片',
            aspectRatioLockEnabled: false,
            resetButtonHidden: false,
          ),
        ],
      );
      return cropped?.path;
    } catch (e) {
      debugPrint('[theme] 裁剪失败（跳过裁剪用原图）：$e');
      return null;
    }
  }

  /// 背景图导入压缩：降采样到最长边 1920（JPEG 质量 85 / 带透明 PNG）。
  /// 解码或编码失败时返回原路径（不阻断导入流程）。
  Future<String> _compressForBackground(String sourcePath) async {
    try {
      final srcBytes = await File(sourcePath).readAsBytes();
      final decoded = img.decodeImage(srcBytes);
      if (decoded == null) return sourcePath;
      var target = decoded;
      const maxEdge = 1920;
      if (target.width > maxEdge || target.height > maxEdge) {
        //按最长边等比缩放（宽 >= 高时以宽为基准，否则以高为基准）
        target = img.copyResize(
          target,
          width: target.width >= target.height ? maxEdge : null,
          height: target.width >= target.height ? null : maxEdge,
          interpolation: img.Interpolation.average,
        );
      }
      //带 alpha（PNG/WebP 等）保持 PNG，否则 JPEG 更小
      final outBytes = target.hasAlpha
          ? img.encodePng(target)
          : img.encodeJpg(target, quality: 85);
      final tmpDir = await getTemporaryDirectory();
      final tmp = File(
          '${tmpDir.path}/bg_compress_${DateTime.now().millisecondsSinceEpoch}.${target.hasAlpha ? 'png' : 'jpg'}');
      await tmp.writeAsBytes(outBytes);
      return tmp.path;
    } catch (e) {
      debugPrint('[theme] 背景图压缩失败（用原图）：$e');
      return sourcePath;
    }
  }

  /// 历史背景图片列表（app 内已复制的全部图片）
  Future<List<String>> listHistoryBackgrounds() {
    return StorageService.listBackgroundImages();
  }

  /// 删除一张历史背景图；若删除的是当前背景，自动回退到默认
  Future<void> deleteBackgroundImage(String path) async {
    await StorageService.deleteBackgroundImage(path);
    if (_palette.backgroundImagePath == path) {
      await setBackgroundImage(null);
    }
    notifyListeners();
  }

  //==================== 主题构建 ====================

  /// 按明暗与自定义构建 ThemeData。
  ///
  /// 配色层级：用户自定义（palette）> 明暗默认色。
  /// - **推荐主题色（seedColor）**驱动主文字/次文字/图标的默认色
  ///   （未自定义时跟随主题色，透明度按亮暗）；自定义后可覆盖。
  /// - **强调色（primary）**：自定义 accent 时用自定义值（所见即所得）；
  ///   未自定义时用 ColorScheme.fromSeed 生成的标准 M3 色调（业界标准）。
  /// M3 组件背景（对话框/BottomSheet/卡片）通过
  /// ColorScheme 的 surfaceContainer 系列传递，保证全局一致。
  ThemeData buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    Color c(PaletteItem item, Color fallback) {
      final v = _palette.colorOf(item);
      return v == null ? fallback : Color(v);
    }

    final accent = seedColor(isDark);
    //文字/图标默认色：
    //- **默认（经典）模式**：不随主题色——日间黑、夜间白（面向喜欢经典的用户）
    //- 推荐色模式：跟随主题色（透明度按明暗：主文字 100%、次文字 70%/54%、
    //  图标 90%/78%）；**浅色主题保护**：主题色亮度 >0.65 时改用标准黑/白
    final Color seedTextBase;
    if (_defaultPreset) {
      seedTextBase = isDark ? Colors.white : Colors.black;
    } else {
      final isSeedLight = accent.computeLuminance() > 0.65;
      seedTextBase =
          isSeedLight ? (isDark ? Colors.white : Colors.black) : accent;
    }
    final seedTextPrimary = seedTextBase;
    final seedTextSecondary = seedTextBase.withValues(alpha: isDark ? 0.70 : 0.54);
    //图标默认加深（用户反馈亮度偏淡：夜间 90%、日间 78%）
    final seedIcon = seedTextBase.withValues(alpha: isDark ? 0.90 : 0.78);
    final background =
        c(PaletteItem.background, isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5));
    final surface =
        c(PaletteItem.surface, isDark ? const Color(0xFF1E1E1E) : Colors.white);
    final textPrimary = c(PaletteItem.textPrimary, seedTextPrimary);
    final textSecondary = c(PaletteItem.textSecondary, seedTextSecondary);
    final iconColor = c(PaletteItem.icon, seedIcon);
    final appBarBg =
        c(PaletteItem.appBar, isDark ? const Color(0xFF1F1F1F) : Colors.white);
    final bottomBarBg =
        c(PaletteItem.bottomBar, isDark ? const Color(0xFF1F1F1F) : Colors.white);
    final drawerBg =
        c(PaletteItem.drawer, isDark ? const Color(0xFF1F1F1F) : Colors.white);
    final dialogBg =
        c(PaletteItem.dialog, isDark ? const Color(0xFF2C2C2C) : Colors.white);
    final divider =
        c(PaletteItem.divider, isDark ? Colors.white12 : Colors.black12);
    //提示条背景（SnackBar / 浮层 AppNotice）默认配色：日间白 / 夜间黑
    //（与页面底色同语义；可自定义：设置 → 主题 → 自定义颜色 → 提示背景）
    final snackbarBg =
        c(PaletteItem.snackbarBg, isDark ? Colors.black : Colors.white);

    //启用背景图时页面底色透明（背景图由全局背景层显示）。
    //注意：只要**任一页面/歌单**有独立背景，也必须让 Scaffold 透明，
    //否则移除全局背景后，逐页背景会被不透明的 Scaffold 遮住。
    final hasAnyBackground = _palette.backgroundImagePath != null ||
        _palette.perPageBackgrounds.values
            .any((e) => e.imagePath != null) ||
        _palette.perPlaylistBackgrounds.values
            .any((e) => e.imagePath != null);
    final scaffoldBg = hasAnyBackground ? Colors.transparent : background;

    //启用背景图时：AppBar / 底部栏完全透明（标题与图标浮在背景图上，
    //遮罩保证可读性）；**抽屉按"抽屉栏遮罩浓度"上色**——日间白遮罩/
    //夜间黑遮罩，浓度越高越不透明（0% 全透明透出背景图，100% 全白/全黑
    //等同未设置背景图）；未启用背景图时抽屉用自定义 drawerBg 实色
    final barTransparent = hasAnyBackground;
    final drawerBgFinal = barTransparent
        ? (isDark ? Colors.black : Colors.white).withValues(
            alpha: isDark
                ? _palette.drawerOverlayAlphaDark
                : _palette.drawerOverlayAlphaLight,
          )
        : drawerBg;

    //强调色：用户自定义 accent 时直接用自定义值（精确指定）；
    //未自定义时——默认模式用经典蓝（与高亮一致），推荐色模式用
    //ColorScheme.fromSeed 生成的标准 M3 primary（业界标准）
    final schemeBase = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    );
    //v1.1-3（用户 2026-10-28 拍板）：默认主题下强调色（主题色）
    //默认 = 日间白 / 夜间黑（用户自定义除外）；推荐色模式用 M3 标准色
    final primary = _palette.colorOf(PaletteItem.accent) != null
        ? accent
        : (_defaultPreset ? (isDark ? Colors.black : Colors.white) : schemeBase.primary);

    //提示条文字默认 = 主题色：默认（经典）模式 = 经典蓝（强调色在默认主题
    //下为日白/夜黑，直接用作文字会在同色背景上不可读）；
    //推荐色模式 = 强调色 primary。与主题设置页"提示文字"预览逻辑一致。
    final snackbarText = c(
        PaletteItem.snackbarText,
        _defaultPreset ? kDefaultHighlightBlue : primary);

    final scheme = schemeBase.copyWith(
      surface: surface,
      onSurface: textPrimary,
      onSurfaceVariant: textSecondary,
      primary: primary,
      onPrimary: _onAccent(primary),
      //M3 组件背景：对话框/BottomSheet/卡片等
      surfaceContainerLowest: background,
      surfaceContainerLow: background,
      surfaceContainer: barTransparent ? Colors.transparent : bottomBarBg,
      surfaceContainerHigh: dialogBg,
      surfaceContainerHighest: dialogBg,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBg,
      appBarTheme: AppBarTheme(
        backgroundColor: barTransparent ? Colors.transparent : appBarBg,
        foregroundColor: textPrimary,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: drawerBgFinal,
      ),
      iconTheme: IconThemeData(color: iconColor),
      //各图标独立配色（未单独设置时回落通用图标色）+ 状态色
      extensions: [
        AppIconColors.fromPalette(_palette, brightness, seedIcon),
        StatusColors.fromPalette(_palette, accent,
            defaultPreset: _defaultPreset),
      ],
      dividerTheme: DividerThemeData(color: divider),
      dialogTheme: DialogThemeData(backgroundColor: dialogBg),
      snackBarTheme: SnackBarThemeData(
        //提示条背景/文字可自定义（设置 → 主题 → 自定义颜色 → 提示背景/提示文字）；
        //SnackBar 与抽屉/页面上的浮层提示（AppNotice）共用这套配色
        backgroundColor: snackbarBg,
        contentTextStyle: TextStyle(color: snackbarText),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        thumbColor: primary,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),
      listTileTheme: const ListTileThemeData(
        //列表行透明，露出页面背景
        tileColor: Colors.transparent,
      ),
    );
  }

  /// 强调色上的前景色（按亮度取黑/白）
  Color _onAccent(Color accent) =>
      accent.computeLuminance() > 0.5 ? Colors.black : Colors.white;

  /// 仅供测试：重置为默认（不碰磁盘）
  @visibleForTesting
  void resetForTest() {
    for (final img in _backgroundImages.values) {
      img.dispose();
    }
    _backgroundImages.clear();
    _backgroundLoadTasks.clear();
    _backgroundLoadPaths.clear();
    _backgroundRetryCounts.clear();
    _themeMode = ThemeMode.system;
    _presetSeed = const Color(0xFF7C4DFF);
    _defaultPreset = false;
    _palette.backgroundImagePath = null;
    _palette.backgroundOverlayAlphaDark = 0.30;
    _palette.backgroundOverlayAlphaLight = 0.0;
    _palette.drawerOverlayAlphaDark = 0.65;
    _palette.drawerOverlayAlphaLight = 0.65;
    _palette.locateOverlayAlpha = 0.0;
    _palette.perPageBackgrounds.clear();
    _palette.perPlaylistBackgrounds.clear();
    for (final item in PaletteItem.values) {
      _palette.clearColor(item);
    }
    _loaded = false;
  }
}
