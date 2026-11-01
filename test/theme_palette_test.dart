import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fs_music_app/models/app_icon_colors.dart';
import 'package:fs_music_app/models/status_colors.dart';
import 'package:fs_music_app/models/theme_palette.dart';
import 'package:fs_music_app/providers/theme_provider.dart';

/// v1.0 主题定制测试：
/// - ThemePalette 序列化（只存非空项 / 损坏数据容错）
/// - ThemeProvider 状态（明暗/推荐色/自定义色/背景图）
/// - buildTheme 明暗默认色 + 用户覆盖 + 背景图透明
///
/// 说明：测试环境无 SharedPreferences 平台通道，持久化调用抛异常被
/// Provider 内部 catch 兜住（状态更新不受影响），与 v0.0 测试模式一致。
void main() {
  group('ThemePalette 序列化', () {
    test('空调色板：JSON 可往返，背景图为 null', () {
      final p = ThemePalette();
      final back = ThemePalette.fromJson(p.toJson());
      expect(back.backgroundImagePath, isNull);
      expect(back.colorOf(PaletteItem.background), isNull);
      expect(back.hasBackgroundImage, isFalse);
    });

    test('自定义颜色往返：只保留已设置项', () {
      final p = ThemePalette()
        ..setColor(PaletteItem.background, 0xFF112233)
        ..setColor(PaletteItem.accent, 0xFF445566);
      final back = ThemePalette.fromJson(p.toJson());
      expect(back.colorOf(PaletteItem.background), 0xFF112233);
      expect(back.colorOf(PaletteItem.accent), 0xFF445566);
      //未设置的项不出现（null）
      expect(back.colorOf(PaletteItem.surface), isNull);
      expect(back.colorOf(PaletteItem.divider), isNull);
    });

    test('清除某项后 JSON 不再包含该项', () {
      final p = ThemePalette()..setColor(PaletteItem.surface, 0xFFFFFFFF);
      p.clearColor(PaletteItem.surface);
      final back = ThemePalette.fromJson(p.toJson());
      expect(back.colorOf(PaletteItem.surface), isNull);
    });

    test('背景图路径往返', () {
      final p = ThemePalette()..backgroundImagePath = '/data/bg_1.png';
      final back = ThemePalette.fromJson(p.toJson());
      expect(back.backgroundImagePath, '/data/bg_1.png');
      expect(back.hasBackgroundImage, isTrue);
    });

    test('遮罩浓度：夜间默认 0.30、日间默认 0.0，可往返，越界自动收敛', () {
      final p = ThemePalette();
      expect(p.backgroundOverlayAlphaDark, 0.30);
      expect(p.backgroundOverlayAlphaLight, 0.0);
      p.backgroundOverlayAlphaDark = 0.75;
      p.backgroundOverlayAlphaLight = 0.25;
      final back = ThemePalette.fromJson(p.toJson());
      expect(back.backgroundOverlayAlphaDark, 0.75);
      expect(back.backgroundOverlayAlphaLight, 0.25);
      //损坏数据：越界值收敛到合法范围
      final bad = ThemePalette.fromJson('{"backgroundOverlayAlphaDark": 5.0}');
      expect(bad.backgroundOverlayAlphaDark, 1.0);
      final bad2 =
          ThemePalette.fromJson('{"backgroundOverlayAlphaLight": -2.0}');
      expect(bad2.backgroundOverlayAlphaLight, 0.0);
    });

    test('抽屉栏遮罩浓度：日/夜默认 0.65，可往返，越界收敛；旧版本无字段取默认', () {
      final p = ThemePalette();
      expect(p.drawerOverlayAlphaDark, 0.65);
      expect(p.drawerOverlayAlphaLight, 0.65);
      p.drawerOverlayAlphaDark = 0.8;
      p.drawerOverlayAlphaLight = 0.4;
      final back = ThemePalette.fromJson(p.toJson());
      expect(back.drawerOverlayAlphaDark, 0.8);
      expect(back.drawerOverlayAlphaLight, 0.4);
      //越界收敛
      final bad = ThemePalette.fromJson('{"drawerOverlayAlphaDark": 3.0}');
      expect(bad.drawerOverlayAlphaDark, 1.0);
      final bad2 = ThemePalette.fromJson('{"drawerOverlayAlphaLight": -1.0}');
      expect(bad2.drawerOverlayAlphaLight, 0.0);
      //旧版本无该字段：保持默认值
      final old = ThemePalette.fromJson('{}');
      expect(old.drawerOverlayAlphaDark, 0.65);
      expect(old.drawerOverlayAlphaLight, 0.65);
    });

    test('旧版单一 backgroundOverlayAlpha 兼容：作为夜间值读取', () {
      //旧版本只有一个字段（默认 0.30）；迁移后读入夜间，日间保持默认 0.0
      final old = ThemePalette.fromJson('{"backgroundOverlayAlpha": 0.6}');
      expect(old.backgroundOverlayAlphaDark, 0.6);
      expect(old.backgroundOverlayAlphaLight, 0.0);
    });

    test('损坏 JSON 不崩溃，返回空调色板', () {
      final back = ThemePalette.fromJson('{{{ 不是 JSON');
      expect(back.backgroundImagePath, isNull);
      expect(back.colorOf(PaletteItem.appBar), isNull);
    });
  });

  group('ThemeProvider 状态', () {
    test('默认值：跟随系统 + 紫 + 无自定义 + 无背景图', () {
      final t = ThemeProvider();
      expect(t.themeMode, ThemeMode.system);
      expect(t.presetSeed, const Color(0xFF7C4DFF));
      expect(t.palette.colorOf(PaletteItem.accent), isNull);
      expect(t.palette.backgroundImagePath, isNull);
      expect(t.loaded, isFalse);
    });

    test('setThemeMode 更新明暗模式', () async {
      final t = ThemeProvider();
      await t.setThemeMode(ThemeMode.light);
      expect(t.themeMode, ThemeMode.light);
      await t.setThemeMode(ThemeMode.dark);
      expect(t.themeMode, ThemeMode.dark);
    });

    test('setPresetSeed 仅接受预设色，拒绝任意色', () async {
      final t = ThemeProvider();
      //不在预设列表中的颜色被忽略
      await t.setPresetSeed(const Color(0xFFABCDEF));
      expect(t.presetSeed, const Color(0xFF7C4DFF));
      await t.setPresetSeed(const Color(0xFF1E88E5));
      expect(t.presetSeed, const Color(0xFF1E88E5));
    });

    test('seedColor 优先自定义强调色', () {
      final t = ThemeProvider();
      expect(t.seedColor(), t.presetSeed);
      t.palette.setColor(PaletteItem.accent, 0xFF112233);
      expect(t.seedColor(), const Color(0xFF112233));
    });

    test('setColor / clearColor 更新自定义项', () async {
      final t = ThemeProvider();
      await t.setColor(PaletteItem.background, const Color(0xFF123456));
      expect(t.palette.colorOf(PaletteItem.background), 0xFF123456);
      await t.clearColor(PaletteItem.background);
      expect(t.palette.colorOf(PaletteItem.background), isNull);
    });

    test('背景图设置与清除', () async {
      final t = ThemeProvider();
      await t.setBackgroundImage('/data/background_images/bg_1.png');
      expect(t.palette.backgroundImagePath, '/data/background_images/bg_1.png');
      await t.setBackgroundImage(null);
      expect(t.palette.backgroundImagePath, isNull);
    });

    test('resetForTest 还原全部默认', () {
      final t = ThemeProvider();
      t.palette.setColor(PaletteItem.accent, 0xFF112233);
      t.palette.backgroundImagePath = '/x.png';
      t.palette.backgroundOverlayAlphaDark = 0.9;
      t.palette.backgroundOverlayAlphaLight = 0.5;
      t.palette.drawerOverlayAlphaDark = 0.9;
      t.palette.drawerOverlayAlphaLight = 0.1;
      t.resetForTest();
      expect(t.themeMode, ThemeMode.system);
      expect(t.presetSeed, const Color(0xFF7C4DFF));
      expect(t.palette.backgroundImagePath, isNull);
      expect(t.palette.backgroundOverlayAlphaDark, 0.30);
      expect(t.palette.backgroundOverlayAlphaLight, 0.0);
      expect(t.palette.drawerOverlayAlphaDark, 0.65);
      expect(t.palette.drawerOverlayAlphaLight, 0.65);
      expect(t.palette.colorOf(PaletteItem.accent), isNull);
      expect(t.loaded, isFalse);
    });

    test('夜间/日间遮罩浓度分别更新并收敛到合法范围', () async {
      final t = ThemeProvider();
      await t.setBackgroundOverlayAlphaDark(0.6);
      expect(t.palette.backgroundOverlayAlphaDark, 0.6);
      await t.setBackgroundOverlayAlphaLight(0.2);
      expect(t.palette.backgroundOverlayAlphaLight, 0.2);
      //越界值收敛
      await t.setBackgroundOverlayAlphaDark(99.0);
      expect(t.palette.backgroundOverlayAlphaDark, 1.0);
      await t.setBackgroundOverlayAlphaLight(-3.0);
      expect(t.palette.backgroundOverlayAlphaLight, 0.0);
    });

    test('抽屉栏遮罩浓度分别更新并收敛到合法范围', () async {
      final t = ThemeProvider();
      await t.setDrawerOverlayAlphaDark(0.85);
      expect(t.palette.drawerOverlayAlphaDark, 0.85);
      await t.setDrawerOverlayAlphaLight(0.35);
      expect(t.palette.drawerOverlayAlphaLight, 0.35);
      //越界值收敛
      await t.setDrawerOverlayAlphaDark(5.0);
      expect(t.palette.drawerOverlayAlphaDark, 1.0);
      await t.setDrawerOverlayAlphaLight(-2.0);
      expect(t.palette.drawerOverlayAlphaLight, 0.0);
    });

    test('提示（SnackBar）主题：默认背景日间白/夜间黑 + 文字=主题色，可自定义', () {
      final t = ThemeProvider();
      var theme = t.buildTheme(Brightness.dark);
      //夜间：黑底
      expect(theme.snackBarTheme.backgroundColor, Colors.black);
      //文字默认 = 主题色（primary）
      expect(theme.snackBarTheme.contentTextStyle?.color,
          theme.colorScheme.primary);
      theme = t.buildTheme(Brightness.light);
      //日间：白底
      expect(theme.snackBarTheme.backgroundColor, Colors.white);
      expect(theme.snackBarTheme.contentTextStyle?.color,
          theme.colorScheme.primary);
      //默认（经典）模式：文字 = 经典蓝（默认模式的强调色）
      t.setPresetSeed(ThemeProvider.kDefaultPresetColor);
      theme = t.buildTheme(Brightness.dark);
      expect(theme.snackBarTheme.contentTextStyle?.color,
          ThemeProvider.kDefaultHighlightBlue);
      //自定义提示背景/文字
      t.palette
        ..setColor(PaletteItem.snackbarBg, 0xFFFF0000)
        ..setColor(PaletteItem.snackbarText, 0xFF00FF00);
      theme = t.buildTheme(Brightness.dark);
      expect(theme.snackBarTheme.backgroundColor, const Color(0xFFFF0000));
      expect(theme.snackBarTheme.contentTextStyle?.color, const Color(0xFF00FF00));
    });
  });

  group('buildTheme 明暗配色', () {
    test('暗色默认：背景 121212 / 列表 1E1E1E / 文字=主题紫 / 弹窗 2C2C2C', () {
      final t = ThemeProvider();
      final theme = t.buildTheme(Brightness.dark);
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, const Color(0xFF121212));
      expect(theme.colorScheme.surface, const Color(0xFF1E1E1E));
      //v1.0：文字默认跟随推荐主题色（紫），可被自定义覆盖
      expect(theme.colorScheme.onSurface, const Color(0xFF7C4DFF));
      expect(theme.colorScheme.surfaceContainerHigh, const Color(0xFF2C2C2C));
      expect(theme.appBarTheme.backgroundColor, const Color(0xFF1F1F1F));
    });

    test('亮色默认：背景 F5F5F5 / 列表白 / 文字=主题紫', () {
      final t = ThemeProvider();
      final theme = t.buildTheme(Brightness.light);
      expect(theme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, const Color(0xFFF5F5F5));
      expect(theme.colorScheme.surface, Colors.white);
      //v1.0：文字默认跟随推荐主题色（紫）
      expect(theme.colorScheme.onSurface, const Color(0xFF7C4DFF));
      expect(theme.appBarTheme.backgroundColor, Colors.white);
    });

    test('自定义 textPrimary 覆盖主题色默认', () {
      final t = ThemeProvider()..palette.setColor(PaletteItem.textPrimary, 0xFF112233);
      final theme = t.buildTheme(Brightness.dark);
      expect(theme.colorScheme.onSurface, const Color(0xFF112233));
    });

    test('自定义覆盖生效：背景/强调色/弹窗', () {
      final t = ThemeProvider();
      t.palette
        ..setColor(PaletteItem.background, 0xFF010203)
        ..setColor(PaletteItem.accent, 0xFFAABBCC)
        ..setColor(PaletteItem.dialog, 0xFFDDEEFF);
      final theme = t.buildTheme(Brightness.dark);
      expect(theme.scaffoldBackgroundColor, const Color(0xFF010203));
      expect(theme.colorScheme.primary, const Color(0xFFAABBCC));
      expect(theme.colorScheme.surfaceContainerHigh, const Color(0xFFDDEEFF));
    });

    test('强调色前景色按亮度取黑/白（未自定义时用 M3 标准 primary）', () {
      final t = ThemeProvider();
      final dark = t.buildTheme(Brightness.light);
      expect(dark.colorScheme.onPrimary, Colors.white); //紫 seed → M3 紫 → 白
      t.palette.setColor(PaletteItem.accent, 0xFFFFFFFF); //自定义白 → 黑
      final light = t.buildTheme(Brightness.light);
      expect(light.colorScheme.onPrimary, Colors.black);
    });

    test('背景图启用时 Scaffold 背景透明', () {
      final t = ThemeProvider()..palette.backgroundImagePath = '/x/bg.png';
      final theme = t.buildTheme(Brightness.dark);
      expect(theme.scaffoldBackgroundColor, Colors.transparent);
    });

    test('背景图启用时 AppBar/底部栏完全透明；抽屉按遮罩浓度（默认 65% 黑遮罩）', () {
      final t = ThemeProvider()..palette.backgroundImagePath = '/x/bg.png';
      final theme = t.buildTheme(Brightness.dark);
      expect(theme.appBarTheme.backgroundColor, Colors.transparent);
      expect(theme.colorScheme.surfaceContainer, Colors.transparent);
      //抽屉：默认遮罩浓度 0.65 的黑色遮罩（夜间黑；值越大越不透明，
      //100% = 全黑，等同未设置背景图）——避免像 50% 实色那样透出底下文字
      final drawer = theme.drawerTheme.backgroundColor!;
      expect(drawer, const Color(0xFF000000).withValues(alpha: 0.65));
      expect(drawer.a, closeTo(0.65, 0.001));
      //列表/弹窗保持实色
      expect(theme.colorScheme.surface.a, 1.0);
      expect(theme.colorScheme.surfaceContainerHigh.a, 1.0);
    });

    test('抽屉遮罩浓度：日间白遮罩 / 夜间黑遮罩，值越大越不透明', () {
      //夜间：黑遮罩 × 浓度
      final t = ThemeProvider()..palette.backgroundImagePath = '/x/bg.png';
      t.palette.drawerOverlayAlphaDark = 0.8;
      var theme = t.buildTheme(Brightness.dark);
      expect(theme.drawerTheme.backgroundColor,
          const Color(0xFF000000).withValues(alpha: 0.8));
      //日间：白遮罩 × 浓度
      t.palette.drawerOverlayAlphaLight = 0.4;
      theme = t.buildTheme(Brightness.light);
      expect(theme.drawerTheme.backgroundColor,
          const Color(0xFFFFFFFF).withValues(alpha: 0.4));
      //100%：完全不透明（全黑/全白，等同未设置背景图）
      t.palette.drawerOverlayAlphaDark = 1.0;
      theme = t.buildTheme(Brightness.dark);
      expect(theme.drawerTheme.backgroundColor!.a, 1.0);
    });

    test('未启用背景图时 AppBar/底部栏/抽屉保持实色', () {
      final t = ThemeProvider();
      final theme = t.buildTheme(Brightness.dark);
      expect(theme.appBarTheme.backgroundColor!.a, 1.0);
      expect(theme.colorScheme.surfaceContainer.a, 1.0);
      expect(theme.drawerTheme.backgroundColor!.a, 1.0);
    });
  });

  group('图标独立自定义', () {
    test('iconColorOf：具体图标 ?? 通用图标 ?? null', () {
      final p = ThemePalette();
      expect(p.iconColorOf(PaletteItem.iconSearch), isNull);
      //设置通用图标 → 所有具体图标继承
      p.setColor(PaletteItem.icon, 0xFF111111);
      expect(p.iconColorOf(PaletteItem.iconSearch), 0xFF111111);
      expect(p.iconColorOf(PaletteItem.iconNext), 0xFF111111);
      //单独设置某个图标 → 覆盖通用
      p.setColor(PaletteItem.iconNext, 0xFF222222);
      expect(p.iconColorOf(PaletteItem.iconNext), 0xFF222222);
      expect(p.iconColorOf(PaletteItem.iconSearch), 0xFF111111);
      //非图标项不受 iconColorOf 回落影响
      expect(p.colorOf(PaletteItem.background), isNull);
    });

    test('AppIconColors 注入 ThemeData：逐个覆盖、回落通用、回落主题色默认', () {
      final t = ThemeProvider();
      //未自定义：各图标回落"主题色 90%"（图标加深：夜间 90%/日间 78%）
      var icons = t.buildTheme(Brightness.dark).extension<AppIconColors>()!;
      expect(icons.search, const Color(0xFF7C4DFF).withValues(alpha: 0.90));
      expect(icons.previous, const Color(0xFF7C4DFF).withValues(alpha: 0.90));
      //单独设置上一首 → 只影响 previous
      t.palette.setColor(PaletteItem.iconPrevious, 0xFFFF0000);
      icons = t.buildTheme(Brightness.dark).extension<AppIconColors>()!;
      expect(icons.previous, const Color(0xFFFF0000));
      expect(icons.next, const Color(0xFF7C4DFF).withValues(alpha: 0.90));
      //设置通用图标 → 其余图标全部继承
      t.palette.setColor(PaletteItem.icon, 0xFF00FF00);
      icons = t.buildTheme(Brightness.dark).extension<AppIconColors>()!;
      expect(icons.search, const Color(0xFF00FF00));
      expect(icons.next, const Color(0xFF00FF00));
      //已单独设置的具体图标仍优先（具体覆盖通用）
      expect(icons.previous, const Color(0xFFFF0000));
    });
  });

  group('状态色 StatusColors', () {
    test('默认值：星标 amber / 收藏红 / 当前歌高亮=主题色互补色', () {
      final t = ThemeProvider();
      final s = t.buildTheme(Brightness.dark).extension<StatusColors>()!;
      expect(s.favoriteStar, const Color(0xFFFFC107));
      expect(s.favoriteRed, const Color(0xFFF44336));
      //默认高亮 = 主题紫的互补色（色相旋转 180°，业界通用方案）
      expect(
        s.currentHighlight,
        StatusColors.complementOf(const Color(0xFF7C4DFF)),
      );
    });

    test('自定义后覆盖默认（星标/收藏红/当前歌高亮）', () {
      final t = ThemeProvider();
      t.palette
        ..setColor(PaletteItem.favoriteStar, 0xFFFF00FF)
        ..setColor(PaletteItem.favoriteRed, 0xFF00FF00)
        ..setColor(PaletteItem.currentHighlight, 0xFF0000FF);
      final s = t.buildTheme(Brightness.dark).extension<StatusColors>()!;
      expect(s.favoriteStar, const Color(0xFFFF00FF));
      expect(s.favoriteRed, const Color(0xFF00FF00));
      expect(s.currentHighlight, const Color(0xFF0000FF));
    });

    test('当前歌高亮未自定义时跟随自定义强调色的互补色', () {
      final t = ThemeProvider();
      t.palette.setColor(PaletteItem.accent, 0xFFAABBCC);
      final s = t.buildTheme(Brightness.dark).extension<StatusColors>()!;
      expect(
        s.currentHighlight,
        StatusColors.complementOf(const Color(0xFFAABBCC)),
      );
    });
  });

  group('默认（经典）模式', () {
    test('setPresetSeed 支持"默认"哨兵，切回具体色恢复', () async {
      final t = ThemeProvider();
      //选"默认"：进入经典模式
      await t.setPresetSeed(ThemeProvider.kDefaultPresetColor);
      expect(t.isDefaultPreset, isTrue);
      //再选具体色：退出经典模式
      await t.setPresetSeed(const Color(0xFF1E88E5));
      expect(t.isDefaultPreset, isFalse);
      expect(t.presetSeed, const Color(0xFF1E88E5));
      //非预设色仍忽略
      await t.setPresetSeed(const Color(0xFF123456));
      expect(t.presetSeed, const Color(0xFF1E88E5));
    });

    test('默认模式：日间黑字/夜间白字、高亮=经典蓝、强调色=日白/夜黑', () {
      final t = ThemeProvider();
      t.setPresetSeed(ThemeProvider.kDefaultPresetColor); //内存生效
      final dark = t.buildTheme(Brightness.dark);
      expect(dark.colorScheme.onSurface, Colors.white);
      final light = t.buildTheme(Brightness.light);
      expect(light.colorScheme.onSurface, Colors.black);
      //当前歌高亮 = 经典蓝（不用互补色）
      final s = dark.extension<StatusColors>()!;
      expect(s.currentHighlight, ThemeProvider.kDefaultHighlightBlue);
      //v1.1-3（用户 2026-10-28）：默认主题下强调色（主题色）未自定义时，
      //夜间 = 黑、日间 = 白（不再是经典蓝）
      expect(dark.colorScheme.primary, Colors.black);
      expect(light.colorScheme.primary, Colors.white);
      //自定义强调色仍生效
      t.palette.setColor(PaletteItem.accent, 0xFFFF0000);
      final custom = t.buildTheme(Brightness.dark);
      expect(custom.colorScheme.primary, const Color(0xFFFF0000));
    });
  });
}
