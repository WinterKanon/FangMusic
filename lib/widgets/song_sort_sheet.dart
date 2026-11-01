import 'package:flutter/material.dart';

import '../models/list_sort_mode.dart';

/// 列表排序方式选择弹窗（v1.2）
///
/// 只返回用户选择，由页面负责保存 + 重排 + 队列同步。
Future<ListSortMode?> showListSortSheet(
  BuildContext context, {
  required ListSortMode current,
  required List<ListSortMode> options,
}) {
  return showModalBottomSheet<ListSortMode>(
    context: context,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        //排序项较多（收藏/歌单最多 9 项）时在小屏会溢出：限制高度并允许滚动
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.82,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  '排序方式',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              for (final m in options)
                ListTile(
                  leading: Icon(sortIcon(m)),
                  title: Text(m.label),
                  trailing: m == current ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.of(ctx).pop(m),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 排序方式图标（共享给页面/弹窗）
IconData sortIcon(ListSortMode mode) {
  switch (mode) {
    case ListSortMode.addTimeAsc:
    case ListSortMode.addTimeDesc:
      return Icons.schedule;
    case ListSortMode.nameAsc:
    case ListSortMode.nameDesc:
      return Icons.sort_by_alpha;
    case ListSortMode.durationAsc:
    case ListSortMode.durationDesc:
      return Icons.timer;
    case ListSortMode.playCountAsc:
    case ListSortMode.playCountDesc:
      return Icons.play_circle_outline;
    case ListSortMode.sourceOrder:
      return Icons.format_list_numbered;
    case ListSortMode.custom:
      return Icons.drag_indicator;
  }
}
