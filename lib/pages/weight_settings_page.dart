import 'package:flutter/material.dart';

import '../models/theme_palette.dart';
import '../models/weight_behavior.dart';
import '../services/weight_config_service.dart';
import '../services/weight_service.dart';
import '../widgets/app_background.dart';

/// 权重调节设置页（v1.0 第二阶段：设置 → 权重调节）
///
/// 分区：
/// 1. **权重范围**：手动权重与所有自动调权的 clamp 边界（默认 [20,500]），
///    两个输入框 + 保存；范围实时作用于所有调权/手动设定/7 天回归。
/// 2. **调权数值**：8 种听歌行为的增量配置（每项可单独修改，
///    "恢复默认"一键还原 docs/02 定稿数值）。
/// 3. **重置权重**：全部歌曲权重一键重置为 100（100 不在范围内时
///    重置到最近边界）；单曲权重在歌曲列表**长按歌曲**设置。
class WeightSettingsPage extends StatefulWidget {
  const WeightSettingsPage({super.key});

  @override
  State<WeightSettingsPage> createState() => _WeightSettingsPageState();
}

class _WeightSettingsPageState extends State<WeightSettingsPage> {
  final WeightConfigService _config = WeightConfigService.instance;

  /// 各行为的调权数值输入控制器（key = 行为）
  final Map<WeightBehavior, TextEditingController> _deltaControllers = {};
  late final TextEditingController _minController;
  late final TextEditingController _maxController;
  //v1.1-2 新增三项配置：标记不喜欢基准值 / 减幅 / 队列移除减幅
  late final TextEditingController _unlikeBaseController;
  late final TextEditingController _unlikeDeltaController;
  late final TextEditingController _queueRemoveDeltaController;

  @override
  void initState() {
    super.initState();
    for (final b in WeightBehavior.values) {
      _deltaControllers[b] =
          TextEditingController(text: _fmt(_config.deltaFor(b)));
    }
    _minController =
        TextEditingController(text: _fmt(_config.minWeight));
    _maxController =
        TextEditingController(text: _fmt(_config.maxWeight));
    _unlikeBaseController =
        TextEditingController(text: _fmt(_config.unlikeBaseWeight));
    _unlikeDeltaController =
        TextEditingController(text: _fmt(_config.unlikeDelta.abs()));
    _queueRemoveDeltaController =
        TextEditingController(text: _fmt(_config.queueRemoveDelta.abs()));
  }

  @override
  void dispose() {
    for (final c in _deltaControllers.values) {
      c.dispose();
    }
    _minController.dispose();
    _maxController.dispose();
    _unlikeBaseController.dispose();
    _unlikeDeltaController.dispose();
    _queueRemoveDeltaController.dispose();
    super.dispose();
  }

  /// 数值显示：整数去掉小数点（30 → "30"），小数保留（如 -150 → "-150"）
  String _fmt(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString();

  /// 解析输入为 double；非法（空/非数字）返回 null
  double? _parse(String text) {
    final v = double.tryParse(text.trim());
    return v;
  }

  /// v1.1-2 新配置项行：左侧说明文字 + 右侧输入框
  Widget _newConfigRow(
    String label,
    String suffixText,
    TextEditingController controller,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 14)),
          ),
          SizedBox(
            width: 120,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                suffixText: suffixText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _saveAll() {
    final config = WeightConfigService.instance;
    var changed = false;
    //保存 8 个事件数值
    for (final entry in _deltaControllers.entries) {
      final v = _parse(entry.value.text);
      if (v != null && v != config.deltaFor(entry.key)) {
        config.setValue(entry.key, v);
        changed = true;
      }
    }
    //保存权重范围（非法输入被 setWeightRange 内部收敛，不崩溃）
    final minV = _parse(_minController.text);
    final maxV = _parse(_maxController.text);
    if (minV != null && maxV != null) {
      config.setWeightRange(minV, maxV);
      changed = true;
      //回填实际生效的范围（收敛后可能与输入不同）
      _minController.text = _fmt(config.minWeight);
      _maxController.text = _fmt(config.maxWeight);
    }
    //v1.1-2 三项新配置（减幅输入显示绝对值，保存时取负数）
    final unlikeBase = _parse(_unlikeBaseController.text);
    if (unlikeBase != null && unlikeBase != config.unlikeBaseWeight) {
      config.setUnlikeBaseWeight(unlikeBase);
      changed = true;
      _unlikeBaseController.text = _fmt(config.unlikeBaseWeight);
    }
    final unlikeDelta = _parse(_unlikeDeltaController.text);
    if (unlikeDelta != null && unlikeDelta != config.unlikeDelta.abs()) {
      config.setUnlikeDelta(-unlikeDelta.abs());
      changed = true;
      _unlikeDeltaController.text = _fmt(config.unlikeDelta.abs());
    }
    final queueRemoveDelta = _parse(_queueRemoveDeltaController.text);
    if (queueRemoveDelta != null &&
        queueRemoveDelta != config.queueRemoveDelta.abs()) {
      config.setQueueRemoveDelta(-queueRemoveDelta.abs());
      changed = true;
      _queueRemoveDeltaController.text = _fmt(config.queueRemoveDelta.abs());
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(changed ? '已保存' : '没有需要保存的修改')));
  }

  void _restoreDefaults() {
    WeightConfigService.instance.restoreDefaults();
    //刷新所有输入框为默认值
    for (final b in WeightBehavior.values) {
      _deltaControllers[b]!.text = _fmt(WeightConfigService.instance.deltaFor(b));
    }
    _minController.text = _fmt(WeightConfigService.instance.minWeight);
    _maxController.text = _fmt(WeightConfigService.instance.maxWeight);
    _unlikeBaseController.text =
        _fmt(WeightConfigService.instance.unlikeBaseWeight);
    _unlikeDeltaController.text =
        _fmt(WeightConfigService.instance.unlikeDelta.abs());
    _queueRemoveDeltaController.text =
        _fmt(WeightConfigService.instance.queueRemoveDelta.abs());
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已恢复全部默认数值')));
  }

  Future<void> _resetAllWeights() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置全部歌曲权重'),
        content: const Text('确定把所有歌曲的权重重置为 100 吗？\n（100 不在配置范围内时重置到最近边界）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await WeightService.instance.resetAllWeights();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已重置全部歌曲权重为 100')));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        //页面级背景（v1.0 补充 17）：背景 + 遮罩在 Scaffold 之下
        const AppBackground(pageKey: ThemePalette.pageKeySettingsPages),
        Scaffold(
          appBar: AppBar(title: const Text('权重调节'), centerTitle: true),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              //==================== 分区1：权重范围 ====================
              Text('权重范围（所有调权/手动设定/回归按此范围收敛）',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _minController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '最小权重',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _maxController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '最大权重',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '当前范围：${_fmt(_config.minWeight)} ~ ${_fmt(_config.maxWeight)}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              //保存：同时保存权重范围与全部 8 个事件调权数值
              FilledButton.icon(
                onPressed: _saveAll,
                icon: const Icon(Icons.save_outlined),
                label: const Text('保存设置'),
              ),
              const Divider(height: 32),

              //==================== 分区2：调权数值 ====================
              Row(
                children: [
                  Expanded(
                    child: Text('调权数值（8 种行为）',
                        style: Theme.of(context).textTheme.titleSmall),
                  ),
                  TextButton(
                    onPressed: _restoreDefaults,
                    child: const Text('恢复默认'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              //调权数值板块的"保存设置"：修改数值后点击才生效
              //（与权重范围板块的保存按钮功能一致，都保存全部配置）
              FilledButton.icon(
                onPressed: _saveAll,
                icon: const Icon(Icons.save_outlined),
                label: const Text('保存设置'),
              ),
              const SizedBox(height: 8),
              for (final b in WeightBehavior.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(b.label, style: const TextStyle(fontSize: 14)),
                      ),
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: _deltaControllers[b],
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                            suffixText: '',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              //==================== v1.1-2 新增：三项配置 ====================
              Text(
                'v1.1 新增（数字均为绝对值，保存后按"减"处理）',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              _newConfigRow(
                '标记不喜欢：基准权重降到',
                '基准值',
                _unlikeBaseController,
              ),
              _newConfigRow(
                '标记不喜欢：当前权重减少',
                '减幅',
                _unlikeDeltaController,
              ),
              _newConfigRow(
                '播放队列移除：普通歌曲权重减少',
                '减幅',
                _queueRemoveDeltaController,
              ),
              const Divider(height: 24),

              //==================== 分区3：重置权重 ====================
              Text('重置', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: _resetAllWeights,
                icon: const Icon(Icons.restart_alt),
                label: const Text('全部歌曲权重重置为 100'),
              ),
              const SizedBox(height: 8),
              Text(
                '单曲权重：在歌曲列表（主页/搜索/收藏/播放队列）中**长按歌曲**即可设置该曲权重',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
