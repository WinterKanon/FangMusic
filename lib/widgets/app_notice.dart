import 'dart:async';

import 'package:flutter/material.dart';

/// 全局浮层提示（v1.0 第三阶段修复）
///
/// 解决两个问题：
/// 1. **层级**：抽屉内操作（新建/重命名/删除歌单等）后用 SnackBar 提示，
///    会被打开的抽屉盖住（SnackBar 挂在 Scaffold 底部，drawer 在其上），
///    观感模糊。本组件用 **root Overlay** 插入浮层，永远显示在抽屉之上。
/// 2. **主题统一**：提示条背景/文字跟随主题的 SnackBarThemeData
///    （设置 → 主题 → 自定义颜色 → 提示背景 / 提示文字），不再固定黑色。
///
/// 用法：`showAppNotice(context, '已创建歌单：xxx')`
/// 浮层显示在屏幕上约 1/5 高度处，淡入淡出，约 1.8 秒后自动消失；
/// 连续调用会先移除旧提示再显示新的。
OverlayEntry? _noticeEntry;
Timer? _noticeTimer;

void showAppNotice(
  BuildContext context,
  String message, {
  Duration duration = const Duration(milliseconds: 1800),
}) {
  //移除旧的提示（连续触发不叠加）
  _noticeEntry?.remove();
  _noticeTimer?.cancel();

  //rootOverlay = MaterialApp 最顶层 Overlay：浮层显示在页面路由与抽屉之上
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _AppNotice(message: message),
  );
  _noticeEntry = entry;
  overlay.insert(entry);
  _noticeTimer = Timer(duration, () {
    if (_noticeEntry == entry) _noticeEntry = null;
    entry.remove();
  });
}

/// 浮层提示本体：顶部偏下居中圆角条，淡入；颜色取主题 SnackBarThemeData
/// （未设置时回退 inverseSurface 反色系，保证任意主题下可读）
class _AppNotice extends StatefulWidget {
  const _AppNotice({required this.message});

  final String message;

  @override
  State<_AppNotice> createState() => _AppNoticeState();
}

class _AppNoticeState extends State<_AppNotice> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    //下一帧再置可见，触发淡入动画
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final snackBarTheme = Theme.of(context).snackBarTheme;
    final bgColor =
        snackBarTheme.backgroundColor ?? Theme.of(context).colorScheme.inverseSurface;
    final textColor =
        snackBarTheme.contentTextStyle?.color ??
        Theme.of(context).colorScheme.onInverseSurface;
    return Positioned(
      //屏幕下部：紧贴底部播放栏上方（底部栏高 100 + 12 间距）。
      //无底部播放栏的页面（设置/主题/背景图片等）也显示在屏幕下部同一位置
      left: 0,
      right: 0,
      bottom: 100 + 12,
      child: Center(
        child: AnimatedOpacity(
          opacity: _visible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 320),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                widget.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(color: textColor, fontSize: 14),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
