import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/audio_playback_service.dart';

/// 播放速度选择（v1.2）
Future<void> showPlaybackSpeedSheet(BuildContext context) async {
  final player = context.read<AudioPlaybackService>();
  final selected = await showModalBottomSheet<double>(
    context: context,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('播放速度',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            for (final s in const [
              0.25,
              0.5,
              0.75,
              1.0,
              1.25,
              1.5,
              1.75,
              2.0,
              3.0,
              5.0
            ])
              ListTile(
                dense: true,
                title: Text(_format(s)),
                trailing: (player.playbackSpeed - s).abs() < 0.001
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.of(ctx).pop(s),
              ),
            ListTile(
              dense: true,
              title: const Text('自定义倍速…'),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () async {
                final custom = await _askCustomSpeed(ctx, player.playbackSpeed);
                if (custom != null && ctx.mounted) Navigator.of(ctx).pop(custom);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
  if (selected != null) {
    await player.setPlaybackSpeed(selected);
  }
}

String _format(double s) {
  final text = s == s.roundToDouble()
      ? s.toStringAsFixed(0)
      : s.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  return 'x$text 倍';
}

Future<double?> _askCustomSpeed(BuildContext context, double current) async {
  final controller =
      TextEditingController(text: _format(current).replaceAll(RegExp(r'[^0-9.]'), ''));
  final result = await showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('自定义倍速'),
      content: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          labelText: '倍速（0.1 - 5.0）',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final v = double.tryParse(controller.text.trim());
            if (v == null || v < 0.1 || v > 5.0) {
              ScaffoldMessenger.of(ctx)
                ..hideCurrentSnackBar()
                ..showSnackBar(const SnackBar(content: Text('请输入 0.1-5.0 的数字')));
              return;
            }
            Navigator.of(ctx).pop(v);
          },
          child: const Text('确定'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}
