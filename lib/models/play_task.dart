/// 播放队列项
///
/// 指向歌曲（songFilePath），并标记是否为"添加下一首"插入的任务。
/// 队列持久化在 `home_play_task_database.json`，读写只经 StorageService。
class PlayTask {
  final String songFilePath;
  final bool isNextSong;

  const PlayTask({required this.songFilePath, this.isNextSong = false});

  factory PlayTask.fromJson(Map<String, dynamic> json) => PlayTask(
        songFilePath: json['songFilePath'] as String? ?? '',
        isNextSong: json['isNextSong'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'songFilePath': songFilePath,
        'isNextSong': isNextSong,
      };
}
