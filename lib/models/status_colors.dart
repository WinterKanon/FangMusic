import 'package:flutter/material.dart';

import 'theme_palette.dart';

/// 状态色扩展（v1.0：收藏星标 / 收藏红 / 当前歌高亮开放自定义）
///
/// 通过 `Theme.of(context).extension<StatusColors>()` 或 `StatusColors.of(context)`
/// 取色。默认值：星标 amber、收藏红红、当前歌高亮 = **主题色互补色**
/// （色相旋转 180°，如主题红 → 高亮蓝绿；浅色互补自动压暗保证对比，
/// 业界通用的"互补色强调"方案）。
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.favoriteStar,
    required this.favoriteRed,
    required this.currentHighlight,
  });

  /// 收藏星标（amber）
  final Color favoriteStar;

  /// 收藏红（"我的收藏"入口等）
  final Color favoriteRed;

  /// 当前播放歌曲高亮（默认 = 主题色互补色）
  final Color currentHighlight;

  /// 主题色互补色：色相旋转 180°；若互补色仍偏浅（亮度 >0.5）则压暗亮度
  /// 到 0.45，保证在浅色背景/主题下高亮依然清晰可见。
  static Color complementOf(Color color) {
    final hsv = HSVColor.fromColor(color);
    final hue = (hsv.hue + 180) % 360;
    var value = hsv.value;
    final candidate =
        HSVColor.fromAHSV(1, hue, hsv.saturation, value).toColor();
    if (candidate.computeLuminance() > 0.5) value = 0.45;
    return HSVColor.fromAHSV(1, hue, hsv.saturation, value).toColor();
  }

  /// 安全取色：主题未注入扩展时回退默认值（测试环境等）。
  static StatusColors of(BuildContext context) {
    final ext = Theme.of(context).extension<StatusColors>();
    if (ext != null) return ext;
    return const StatusColors(
      favoriteStar: Color(0xFFFFC107),
      favoriteRed: Color(0xFFF44336),
      currentHighlight: Color(0xFF7C4DFF),
    );
  }

  /// 由调色板 + 主题色构建（自定义 ?? 默认）。
  /// [defaultPreset] 为"默认（经典）模式"时，当前歌高亮默认用经典蓝
  /// （不用互补色——互补色在经典黑白文字下会不明显），可自定义覆盖。
  factory StatusColors.fromPalette(
    ThemePalette palette,
    Color accent, {
    bool defaultPreset = false,
  }) {
    final starValue = palette.colorOf(PaletteItem.favoriteStar);
    final redValue = palette.colorOf(PaletteItem.favoriteRed);
    final highlightValue = palette.colorOf(PaletteItem.currentHighlight);
    final highlightFallback = defaultPreset
        ? const Color(0xFF2196F3) //经典蓝
        : complementOf(accent);
    return StatusColors(
      favoriteStar: starValue != null ? Color(starValue) : const Color(0xFFFFC107),
      favoriteRed: redValue != null ? Color(redValue) : const Color(0xFFF44336),
      currentHighlight:
          highlightValue != null ? Color(highlightValue) : highlightFallback,
    );
  }

  @override
  StatusColors copyWith({
    Color? favoriteStar,
    Color? favoriteRed,
    Color? currentHighlight,
  }) {
    return StatusColors(
      favoriteStar: favoriteStar ?? this.favoriteStar,
      favoriteRed: favoriteRed ?? this.favoriteRed,
      currentHighlight: currentHighlight ?? this.currentHighlight,
    );
  }

  @override
  StatusColors lerp(ThemeExtension<StatusColors>? other, double t) {
    if (other is! StatusColors) return this;
    return StatusColors(
      favoriteStar: Color.lerp(favoriteStar, other.favoriteStar, t)!,
      favoriteRed: Color.lerp(favoriteRed, other.favoriteRed, t)!,
      currentHighlight:
          Color.lerp(currentHighlight, other.currentHighlight, t)!,
    );
  }
}
