/// 单曲权重数据（v1.1 独立权重库：`weights.json`）
///
/// 与歌曲库（songs.json）**解耦**持久化：歌曲库损坏/被清空时
/// 权重不丢失；删除歌曲时按路径清理对应记录。
///
/// - [weight]：当前权重（事件调权/手动设定/衰减/回归的目标值）
/// - [baseWeight]：基准权重（默认 100；"标记不喜欢"把它降为配置值，
///   7 天回归的目标 = 基准，而非固定 100）
/// - [lastWeightIncreaseTime] / [lastWeightDecreaseTime]：
///   最后一次增加/减少时间（7 天回归的观察期依据）
class SongWeightData {
  final double weight;
  final double baseWeight;
  final String lastWeightIncreaseTime;
  final String lastWeightDecreaseTime;

  const SongWeightData({
    required this.weight,
    this.baseWeight = 100.0,
    this.lastWeightIncreaseTime = '',
    this.lastWeightDecreaseTime = '',
  });

  factory SongWeightData.fromJson(Map<String, dynamic> json) {
    return SongWeightData(
      weight: (json['weight'] as num?)?.toDouble() ?? 100.0,
      baseWeight: (json['baseWeight'] as num?)?.toDouble() ?? 100.0,
      lastWeightIncreaseTime:
          json['lastWeightIncreaseTime'] as String? ?? '',
      lastWeightDecreaseTime:
          json['lastWeightDecreaseTime'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'weight': double.parse(weight.toStringAsFixed(2)),
      'baseWeight': double.parse(baseWeight.toStringAsFixed(2)),
      'lastWeightIncreaseTime': lastWeightIncreaseTime,
      'lastWeightDecreaseTime': lastWeightDecreaseTime,
    };
  }

  SongWeightData copyWith({
    double? weight,
    double? baseWeight,
    String? lastWeightIncreaseTime,
    String? lastWeightDecreaseTime,
  }) {
    return SongWeightData(
      weight: weight ?? this.weight,
      baseWeight: baseWeight ?? this.baseWeight,
      lastWeightIncreaseTime:
          lastWeightIncreaseTime ?? this.lastWeightIncreaseTime,
      lastWeightDecreaseTime:
          lastWeightDecreaseTime ?? this.lastWeightDecreaseTime,
    );
  }
}
