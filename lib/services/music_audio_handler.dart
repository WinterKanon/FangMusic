import 'package:audio_service/audio_service.dart';

import 'audio_playback_service.dart';

/// 通知栏/锁屏媒体处理器（v1.2：改用 audio_service 自建处理器）。
///
/// 为什么不继续用 just_audio_background：它硬性限制单 AudioPlayer 实例，
/// 无法实现双播放器零间隙换源。这里由本处理器统一驱动通知栏，
/// 主/备播放器交换对系统透明（状态与队列由 [AudioPlaybackService] 推送）。
class MusicAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  static MusicAudioHandler? instance;

  MusicAudioHandler() {
    instance = this;
    //初始状态：空闲、仅显示播放键（避免系统拿到空 playbackState）
    playbackState.add(PlaybackState(
      controls: const [MediaControl.play],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0],
      processingState: AudioProcessingState.idle,
      playing: false,
      updatePosition: Duration.zero,
    ));
  }

  AudioPlaybackService get _service => AudioPlaybackService.instance;

  @override
  Future<void> play() => _service.resume();

  @override
  Future<void> pause() => _service.pause();

  @override
  Future<void> seek(Duration position) => _service.seek(position);

  @override
  Future<void> skipToNext() => _service.skipToNextInPool();

  @override
  Future<void> skipToPrevious() => _service.skipToPreviousInPool();

  @override
  Future<void> skipToQueueItem(int index) => _service.skipToIndex(index);

  @override
  Future<void> stop() async {
    await _service.stopPlayback();
    await super.stop();
  }

  //播放模式由 app 自身队列管理（随机批次/单曲循环），系统重复/随机开关
  //不改变池形状，忽略即可。
  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {}

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {}
}
