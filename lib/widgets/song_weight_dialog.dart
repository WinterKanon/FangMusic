import 'package:flutter/material.dart';

import '../models/song.dart';
import '../services/weight_config_service.dart';
import '../services/weight_service.dart';
import 'app_notice.dart';

/// 单曲权重设置弹窗（v1.0 第二阶段，第三阶段抽为公共组件）
///
/// **独立 StatefulWidget**（而非 StatefulBuilder）：TextEditingController 与
/// 滑块值由 State 自己持有并在 [dispose] 释放，生命周期随弹窗路由
/// （含关闭过渡动画）自然结束——彻底规避"外部 controller 被提前
/// dispose → 弹窗反向动画期间 TextField 重建"导致的 `_dependents.isEmpty`
/// 断言崩溃（此坑在第二阶段修过）。
///
/// 边界处理：
/// - 输入**非数字**：提示"请输入有效数字"，弹窗不关闭
/// - 输入**超出范围**（如范围 200~500 填 550）：滑块即时收敛到边界，
///   保存时经 [WeightConfigService.clampWeight] 收敛后落库，并返回实际生效值
/// - "重置 100"：100 不在范围内时自动取最近边界（clampRange）
///
/// 结果经 pop 返回值传出：true=已重置、double=已保存（收敛后的实际值）、null=取消。
class SongWeightDialog extends StatefulWidget {
  const SongWeightDialog({super.key, required this.song});

  final Song song;

  @override
  State<SongWeightDialog> createState() => _SongWeightDialogState();
}

class _SongWeightDialogState extends State<SongWeightDialog> {
  final WeightConfigService _config = WeightConfigService.instance;

  /// 当前权重（弹窗打开时读取）
  late final double _current =
      WeightService.instance.weightOf(widget.song.audioFilePath) ?? 100.0;

  /// 滑块当前值：初始 = 当前权重收敛到配置范围（保证 Slider value 合法）
  late double _value =
      _current.clamp(_config.minWeight, _config.maxWeight).toDouble();

  /// 输入框控制器（State 生命周期内创建/释放）
  late final TextEditingController _controller =
      TextEditingController(text: _value.round().toString());

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    //强调色（主题色）：进度条/按钮统一使用，可自定义（设置 → 主题 → 强调色）
    final primary = Theme.of(context).colorScheme.primary;
    return AlertDialog(
      title: Text(
        '设置权重：${widget.song.name}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '当前权重：${_current.round()}\n'
            '基准权重：${(WeightService.instance.baseWeightOf(widget.song.audioFilePath) ?? 100.0).round()}\n'
            '范围：${_config.minWeight.round()} ~ ${_config.maxWeight.round()}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          //滑块：随配置范围实时变化（拖拽/输入框双向同步）。
          //样式与底部播放栏进度条一致：轨道细(2)、圆点小(6)、
          //已播放侧=强调色、未播放侧=同色偏灰（v1.0 第三阶段优化）
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: primary,
              thumbColor: primary,
              inactiveTrackColor: _greyish(primary),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              trackHeight: 2,
            ),
            child: Slider(
              min: _config.minWeight,
              max: _config.maxWeight,
              value: _value,
              onChanged: (v) => setState(() {
                _value = v;
                _controller.text = v.round().toString();
              }),
            ),
          ),
          const SizedBox(height: 8),
          //输入框：手动精确输入，合法时同步滑块并收敛到边界
          TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '权重值',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (t) {
              final v = double.tryParse(t.trim());
              if (v != null) {
                setState(() =>
                    _value = v.clamp(_config.minWeight, _config.maxWeight).toDouble());
              }
            },
          ),
          const SizedBox(height: 4),
          Text(
            '输入超出范围时自动收敛到边界',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        //按钮颜色统一用主题色（强调色）：取消/重置 100 = 主题色文字，
        //保存 = 主题色背景（v1.0 第三阶段优化）
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: primary,
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: primary,
          ),
          onPressed: () {
            //重置为 100（不在范围内时取最近边界）
            WeightService.instance.resetSongWeight(widget.song);
            Navigator.of(context).pop(true);
          },
          child: const Text('重置 100'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: _onPrimary(primary),
          ),
          onPressed: () {
            final v = double.tryParse(_controller.text.trim());
            if (v == null) {
              //非数字输入：浮层提示（显示在弹窗之上 + 主题色），弹窗不关闭
              showAppNotice(context, '请输入有效数字');
              return;
            }
            //按配置范围收敛后落库，并返回实际生效值（越界如 550 → 500）
            final saved = _config.clampWeight(v);
            WeightService.instance.setManualWeight(widget.song, saved);
            Navigator.of(context).pop(saved);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }

  /// 强调色/主题色的"偏灰"版本：饱和度降到 25%，再降透明度到 35%——
  /// 与底部播放栏进度条未播放部分同规则（有颜色但偏灰偏淡，随主题色变化）
  Color _greyish(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withSaturation(hsl.saturation * 0.25)
        .toColor()
        .withValues(alpha: 0.35);
  }

  /// 强调色上的前景色（按亮度取黑/白，与 buildTheme._onAccent 同规则）
  Color _onPrimary(Color primary) =>
      primary.computeLuminance() > 0.5 ? Colors.black : Colors.white;
}
