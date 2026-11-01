import 'package:flutter/material.dart';

/// 记录"最近一次进入的主页/收藏页/歌单详情页"（v1.0 第四阶段：默认停留页面）
///
/// 只跟踪带 RouteSettings.name 的**目标页**（favorites / playlist + 歌单 id）；
/// home 根页 name 为空但逻辑上算主页（currentName 初始 'home'，pop 回根时
/// 也归 'home'）。设置/搜索/关于等页面 name 为空 → 不覆盖记录，
/// 保留用户最近一次停留的目标页（符合需求：只记主页/收藏/歌单页）。
class LastPageObserver extends NavigatorObserver {
  /// 当前（栈顶目标页）记录值；初始 = 主页
  String currentName = 'home';

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = route.settings.name;
    if (name != null && name.isNotEmpty) currentName = name;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = previousRoute?.settings.name;
    if (name != null && name.isNotEmpty) {
      currentName = name;
    } else {
      currentName = 'home'; //回到根（主页）
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = previousRoute?.settings.name;
    if (name != null && name.isNotEmpty) {
      currentName = name;
    } else {
      currentName = 'home';
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final name = newRoute?.settings.name;
    if (name != null && name.isNotEmpty) currentName = name;
  }
}
