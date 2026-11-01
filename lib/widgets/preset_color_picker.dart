import 'package:flutter/material.dart';

import '../providers/theme_provider.dart';

/// 系统推荐主题色选择器（v1.0：默认（经典）选项 + 色系 → 具体色两级选择）
///
/// 一级：**"默认"块**（与色系同级，经典模式：日间黑字/夜间白字，不随主题色）
/// + 各色系块（代表色圆 + 色系名文字；当前选中色所在色系描边高亮）
/// 点击色系 → 弹出该色系的小弹窗，列出 5~10 种具体色（色块 + 色名），
/// 点击某色即选中并关闭。
///
/// 主页主题弹窗与主题设置页共用此组件，保证两处交互一致。
class PresetColorPicker extends StatelessWidget {
  const PresetColorPicker({
    super.key,
    required this.selected,
    required this.onSelect,
    this.defaultSelected = false,
  });

  /// 当前选中的推荐色
  final Color selected;

  /// 选中某具体色时回调（由调用方 setPresetSeed 持久化）
  final ValueChanged<Color> onSelect;

  /// 是否处于"默认"（经典）模式（"默认"块高亮）
  final bool defaultSelected;

  /// 当前选中色所属的色系（找不到返回 null）
  ThemePresetGroup? _groupOf(Color color) {
    for (final g in ThemeProvider.presetGroups) {
      for (final c in g.colors) {
        if (c.color == color) return g;
      }
    }
    return null;
  }

  /// 色系代表色 = 该色系第一个颜色
  Color _groupColor(ThemePresetGroup g) => g.colors.first.color;

  @override
  Widget build(BuildContext context) {
    //默认模式下仅"默认"块高亮，色系块不再打勾（否则"默认"与旧色系同时有勾）
    final activeGroup = defaultSelected ? null : _groupOf(selected);
    return Wrap(
      spacing: 14,
      runSpacing: 16,
      children: [
        //"默认"（经典）选项：与色系同级；圆 = 左黑右白对角渐变示意
        //（日间黑字/夜间白字），选中时描边 + 对勾
        GestureDetector(
          onTap: () => onSelect(ThemeProvider.kDefaultPresetColor),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Colors.black, Colors.white],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: defaultSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: defaultSelected
                    ? const Icon(Icons.check, size: 20, color: Colors.grey)
                    : null,
              ),
              const SizedBox(height: 4),
              const Text('默认', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
        for (final g in ThemeProvider.presetGroups)
          GestureDetector(
            onTap: () => _openGroup(context, g),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                //色系代表色圆；当前选中色在该系时描边高亮
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _groupColor(g),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: identical(activeGroup, g)
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: identical(activeGroup, g)
                      ? Icon(
                          Icons.check,
                          size: 20,
                          color: _groupColor(g).computeLuminance() > 0.5
                              ? Colors.black
                              : Colors.white,
                        )
                      : null,
                ),
                const SizedBox(height: 4),
                //色系名（如"红色系"）
                Text(g.name, style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
      ],
    );
  }

  /// 展开色系小弹窗：该色系全部具体色（色块 + 色名），点击选中
  Future<void> _openGroup(BuildContext context, ThemePresetGroup group) {
    return showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                group.name,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 16,
                children: [
                  for (final c in group.colors)
                    GestureDetector(
                      onTap: () {
                        onSelect(c.color);
                        Navigator.of(ctx).pop();
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: c.color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: c.color == selected && !defaultSelected
                                    ? Theme.of(ctx).colorScheme.primary
                                    : Theme.of(ctx).colorScheme.outline,
                                width: c.color == selected && !defaultSelected
                                    ? 3
                                    : 1,
                              ),
                            ),
                            child: c.color == selected && !defaultSelected
                                ? Icon(
                                    Icons.check,
                                    size: 18,
                                    color: c.color.computeLuminance() > 0.5
                                        ? Colors.black
                                        : Colors.white,
                                  )
                                : null,
                          ),
                          const SizedBox(height: 4),
                          //具体色名（如"血红""深红"）
                          Text(c.name, style: const TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
