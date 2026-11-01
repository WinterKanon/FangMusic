import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/theme_palette.dart';
import '../providers/theme_provider.dart';

/// 页面级背景层（v1.0 补充 17 方案 A + v1.1-3 逐页背景）
///
/// 每个页面 Scaffold 之下挂一层背景（Stack[背景图 + 遮罩]），
/// **页面出现即带背景**。v1.1-3 起支持**按页面/播放源/歌单**取不同背景：
/// - [pageKey]：页面作用范围（ThemePalette.pageKeyXxx 常量）；
/// - [queueKey]：播放队列页源级 Key（queue:allSongs / queue:favorites /
///   queue:pl:歌单id，优先于 [pageKey]）；
/// - [playlistId]：自定义歌单页（内部转 pl:歌单id Key）；
/// - 三者都空 = 全局默认背景（旧行为）。
/// 取背景：精确配置 → 层级回退（queue:xx → queue → 全局）→ 全局默认。
///
/// 背景图显示策略（关键）：
/// - 内存已解码的 ui.Image 直接用 **RawImage**（不经 ImageCache，
///   不会被系统内存压力清空，切页零延迟、恒显示）；
/// - 解码未就绪时先显示遮罩纯色（日间白/夜间黑），解码完成后自动出现；
/// - **不再用 Image.file 兜底**（FileImage 依赖 ImageCache，真机内存压力下
///   每次切页 miss 重新解码 → 用户看到的"纯色 → 背景突然加载"）。
class AppBackground extends StatelessWidget {
  const AppBackground({
    super.key,
    this.pageKey,
    this.queueKey,
    this.playlistId,
  });

  /// 页面 Key（主页/收藏/搜索/设置页/JSON/关于等；null = 全局默认背景）
  final String? pageKey;

  /// 播放队列源级 Key（queue:allSongs / queue:favorites / queue:pl:歌单id；
  /// 传入后优先于 [pageKey]）
  final String? queueKey;

  /// 自定义歌单 id（内部生成 pl:歌单id 作用范围 Key）
  final String? playlistId;

  /// 解析本组件的作用范围 Key
  String? get _scopeKey {
    if (queueKey != null) return queueKey;
    if (playlistId != null) return ThemePalette.playlistKey(playlistId!);
    return pageKey;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeProvider theme;
    try {
      theme = context.watch<ThemeProvider>();
    } on ProviderNotFoundException {
      //独立构建场景（如单元测试直接 pump 页面、无 Provider 树）：
      //降级为空背景，不影响页面其余部分构建
      return const SizedBox.shrink();
    }
    final scopeKey = _scopeKey;
    //作用范围解析：指定了 scopeKey 走"精确→回退→全局"，否则直接用全局
    final bgPath = scopeKey == null
        ? theme.palette.backgroundImagePath
        : theme.effectiveBackgroundPath(scopeKey);
    //未启用背景图：铺一层不透明页面底色。
    //（全局背景移除但仍有逐页背景时，Scaffold 会透明；本层保证未配置
    // 背景的页面不会透出黑色路由底）
    if (bgPath == null) {
      return Positioned.fill(
        child: ColoredBox(color: Theme.of(context).colorScheme.surface),
      );
    }

    //遮罩浓度按当前明暗模式分别配置：
    //**日间=白色遮罩**（值越大背景越白，100=全白=未设背景图效果）
    //**夜间=黑色遮罩**（值越大背景越黑，100=全黑=未设背景图效果）
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final alpha = scopeKey == null
        ? (isDark
            ? theme.palette.backgroundOverlayAlphaDark
            : theme.palette.backgroundOverlayAlphaLight)
        : theme.effectiveBackgroundMask(scopeKey, isDark);
    final decoded = theme.backgroundImageForPath(bgPath);
    //首次进入某页（该图尚未解码）：下一帧触发异步解码，完成后 notify → 背景出现
    if (decoded == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        theme.ensureBackgroundImageByPath(bgPath);
      });
    }

    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          //背景图：decoded 就绪即 RawImage（恒显示，切页零延迟）；
          //未就绪显示透明（解码完成 notify 后自动出现，不闪回默认背景）
          if (decoded != null)
            RawImage(image: decoded, fit: BoxFit.cover)
          else
            const ColoredBox(color: Colors.transparent),
          //半透明遮罩：保证前景文字/控件可读；浓度用户可调（明暗分开）
          ColoredBox(
            color: isDark
                ? Colors.black.withValues(alpha: alpha)
                : Colors.white.withValues(alpha: alpha),
          ),
        ],
      ),
    );
  }
}
