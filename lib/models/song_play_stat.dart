/// 单曲播放统计（v1.2）
class SongPlayStat {
  const SongPlayStat({
    this.playCount = 0,
    this.lastPlayedAt = '',
  });

  final int playCount;
  final String lastPlayedAt;

  SongPlayStat copyWith({int? playCount, String? lastPlayedAt}) {
    return SongPlayStat(
      playCount: playCount ?? this.playCount,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'playCount': playCount,
        'lastPlayedAt': lastPlayedAt,
      };

  factory SongPlayStat.fromJson(Map<String, dynamic> json) {
    return SongPlayStat(
      playCount: (json['playCount'] as num?)?.toInt() ?? 0,
      lastPlayedAt: json['lastPlayedAt'] as String? ?? '',
    );
  }
}
