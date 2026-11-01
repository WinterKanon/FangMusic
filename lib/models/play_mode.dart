import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 播放模式（4 种）
///
/// - sequence 顺序播放：按队列顺序，最后一首播完回到第一首
/// - repeatOne 单曲循环：当前歌循环
/// - realRandom 普通随机：等概率随机批次
/// - weightedRandom 加权随机：按权重概率随机（算法阶段4 实现，
///   阶段3 中 UI 置灰不可选）
enum PlayMode {
  sequence('顺序播放', Icons.repeat),
  repeatOne('单曲循环', Icons.repeat_one),
  realRandom('普通随机', Icons.shuffle),
  weightedRandom('加权随机', Icons.casino);

  const PlayMode(this.label, this.icon);

  /// 中文标签（弹窗/按钮显示）
  final String label;

  /// 图标（底部栏模式按钮/弹窗显示）
  final IconData icon;

  static const _prefKey = 'play_mode';

  /// 从偏好读取当前模式（默认顺序播放；读取失败也回退默认）
  static Future<PlayMode> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return fromName(prefs.getString(_prefKey));
    } catch (_) {
      return PlayMode.sequence;
    }
  }

  /// 按存储名解析（未知值回退顺序播放）
  static PlayMode fromName(String? name) {
    return PlayMode.values.firstWhere(
      (m) => m.name == name,
      orElse: () => PlayMode.sequence,
    );
  }

  /// 持久化当前模式
  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, name);
    } catch (_) {
      //偏好写入失败不影响使用
    }
  }
}
