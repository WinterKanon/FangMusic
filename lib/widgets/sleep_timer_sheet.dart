import 'package:flutter/material.dart';

import '../services/sleep_timer_service.dart';

/// 睡眠定时弹窗（v1.2）
Future<void> showSleepTimerSheet(BuildContext context) {
  final service = SleepTimerService.instance;
  final customController = TextEditingController();
  var mode = service.mode;
  var customError = '';
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              16, 12, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('睡眠定时',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  if (service.active)
                    TextButton(
                      onPressed: () {
                        service.cancel();
                        Navigator.of(ctx).pop();
                      },
                      child: const Text('取消定时'),
                    ),
                ],
              ),
              if (service.active) ...[
                Text(
                  service.pendingPause
                      ? '已到时间，等待当前歌曲播完'
                      : '剩余 ${service.remainingLabel} · ${service.mode.label}',
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 4),
              const Text('结束方式'),
              RadioGroup<SleepTimerMode>(
                groupValue: mode,
                onChanged: (v) => setState(() => mode = v ?? mode),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    RadioListTile<SleepTimerMode>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: SleepTimerMode.pauseNow,
                      title: Text('到时间立即暂停'),
                    ),
                    RadioListTile<SleepTimerMode>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: SleepTimerMode.finishCurrent,
                      title: Text('播完当前歌曲再暂停'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final minutes in const [15, 30, 45, 60, 90])
                    ActionChip(
                      label: Text('$minutes 分钟'),
                      onPressed: () {
                        service.start(Duration(minutes: minutes), mode);
                        Navigator.of(ctx).pop();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: customController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '自定义时长（1-120 分钟）',
                        errorText: customError.isEmpty ? null : customError,
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      final n = int.tryParse(customController.text.trim());
                      if (n == null || n < 1 || n > 120) {
                        setState(() => customError = '请输入 1-120 的整数');
                        return;
                      }
                      service.start(Duration(minutes: n), mode);
                      Navigator.of(ctx).pop();
                    },
                    child: const Text('开始'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
