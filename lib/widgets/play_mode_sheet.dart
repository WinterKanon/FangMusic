import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/play_mode.dart';
import '../services/audio_playback_service.dart';
import '../services/playlist_service.dart';

/// 播放模式选择弹窗（v1.2 抽取共享）
///
/// 列表信息栏 / 播放界面 / 底部栏都调用本函数，避免三处各写一份。
Future<void> showPlayModeSheet(BuildContext context) async {
  final playlist = context.read<PlaylistService>();
  final selected = await showModalBottomSheet<PlayMode>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              '播放模式',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          for (final m in PlayMode.values)
            ListTile(
              leading: Icon(m.icon),
              title: Text(m.label),
              trailing: m == playlist.mode ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(ctx).pop(m),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (selected == null || !context.mounted) return;
  await playlist.setMode(selected);
  if (!context.mounted) return;
  await context.read<AudioPlaybackService>().onModeChanged();
}
