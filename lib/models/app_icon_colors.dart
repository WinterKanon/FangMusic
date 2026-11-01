import 'package:flutter/material.dart';

import 'theme_palette.dart';

/// 图标颜色扩展（v1.0：每个图标可单独自定义颜色）
///
/// 通过 `Theme.of(context).extension<AppIconColors>()!` 取色。
/// 各具体图标色未自定义时回落到"通用图标"色，通用图标色未自定义时
/// 回落明暗默认（白70%/黑54%），由 [buildTheme] 构建时算好。
class AppIconColors extends ThemeExtension<AppIconColors> {
  const AppIconColors({
    required this.search,
    required this.previous,
    required this.next,
    required this.playPause,
    required this.mode,
    required this.queue,
    required this.more,
    required this.settings,
    required this.add,
    required this.generic,
  });

  /// 搜索图标
  final Color search;

  /// 上一首图标
  final Color previous;

  /// 下一首图标
  final Color next;

  /// 播放/暂停图标
  final Color playPause;

  /// 播放模式图标（循环/随机/单曲）
  final Color mode;

  /// 播放队列/排序图标
  final Color queue;

  /// 更多操作图标（三点）
  final Color more;

  /// 设置图标（齿轮）
  final Color settings;

  /// 添加图标（加号）
  final Color add;

  /// 通用图标（未单独归类的图标兜底色）
  final Color generic;

  /// 安全取色：主题未注入扩展（如某些测试环境）时回退 iconTheme 通用色，
  /// 避免空指针。页面统一用 `AppIconColors.of(context)` 取色。
  static AppIconColors of(BuildContext context) {
    final ext = Theme.of(context).extension<AppIconColors>();
    if (ext != null) return ext;
    final fallback = Theme.of(context).iconTheme.color ?? Colors.black54;
    return AppIconColors(
      search: fallback,
      previous: fallback,
      next: fallback,
      playPause: fallback,
      mode: fallback,
      queue: fallback,
      more: fallback,
      settings: fallback,
      add: fallback,
      generic: fallback,
    );
  }

  /// 由调色板构建（具体项 ?? 通用图标 ?? [fallbackIcon]）。
  /// [fallbackIcon] 为"通用图标默认色"——v1.0 推荐主题色驱动时传入
  /// 主题色的降透明度版本（如紫 70%）。
  factory AppIconColors.fromPalette(
    ThemePalette palette,
    Brightness brightness,
    Color fallbackIcon,
  ) {
    final genericValue = palette.iconColorOf(PaletteItem.icon);
    final generic = genericValue != null ? Color(genericValue) : fallbackIcon;
    Color from(PaletteItem item) {
      final v = palette.iconColorOf(item);
      return v != null ? Color(v) : generic;
    }
    return AppIconColors(
      search: from(PaletteItem.iconSearch),
      previous: from(PaletteItem.iconPrevious),
      next: from(PaletteItem.iconNext),
      playPause: from(PaletteItem.iconPlayPause),
      mode: from(PaletteItem.iconMode),
      queue: from(PaletteItem.iconQueue),
      more: from(PaletteItem.iconMore),
      settings: from(PaletteItem.iconSettings),
      add: from(PaletteItem.iconAdd),
      generic: generic,
    );
  }

  @override
  AppIconColors copyWith({
    Color? search,
    Color? previous,
    Color? next,
    Color? playPause,
    Color? mode,
    Color? queue,
    Color? more,
    Color? settings,
    Color? add,
    Color? generic,
  }) {
    return AppIconColors(
      search: search ?? this.search,
      previous: previous ?? this.previous,
      next: next ?? this.next,
      playPause: playPause ?? this.playPause,
      mode: mode ?? this.mode,
      queue: queue ?? this.queue,
      more: more ?? this.more,
      settings: settings ?? this.settings,
      add: add ?? this.add,
      generic: generic ?? this.generic,
    );
  }

  @override
  AppIconColors lerp(ThemeExtension<AppIconColors>? other, double t) {
    if (other is! AppIconColors) return this;
    return AppIconColors(
      search: Color.lerp(search, other.search, t)!,
      previous: Color.lerp(previous, other.previous, t)!,
      next: Color.lerp(next, other.next, t)!,
      playPause: Color.lerp(playPause, other.playPause, t)!,
      mode: Color.lerp(mode, other.mode, t)!,
      queue: Color.lerp(queue, other.queue, t)!,
      more: Color.lerp(more, other.more, t)!,
      settings: Color.lerp(settings, other.settings, t)!,
      add: Color.lerp(add, other.add, t)!,
      generic: Color.lerp(generic, other.generic, t)!,
    );
  }
}
