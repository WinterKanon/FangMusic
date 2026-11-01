/// 歌曲数据模型（纯数据，不含任何读写逻辑）
///
/// 全部字段一次建齐：
/// - 基础字段：阶段1 使用（导入、列表展示）
/// - 权重字段：阶段4 加权随机使用（此处预留，避免后期改模型）
///
/// 序列化（fromJson / toJson）集中在本文件，
/// 文件读写只在 [StorageService] 中发生。
class Song {
  final String name; //歌名（直接显示，不拆分歌名/歌手）
  final String audioFilePath; //音频文件路径（持久目录，长期有效）
  final String coverImagePath; //封面图片路径（预留，阶段5+）
  final String lyricsFilePath; //歌词文件路径（预留）
  final String addTime; //添加时间（ISO 8601 字符串）
  final int duration; //音频时长（毫秒）
  final bool isFavorite; //是否收藏（阶段5 使用）
  final int sortNumber; //排序编号（1,2,3…）
  final int fileSize; //文件大小（字节），与 name 组成去重键
  final double weight; //当前权重值（默认 100.0，范围由权重配置决定；阶段4 使用）
  final double baseWeight; //基准权重（v1.1 新增：默认 100.0；"标记不喜欢"把基准降为配置值；
  //7 天回归回到基准而非 100；歌曲库字段仅为兼容展示，**权威在 weights.json**）
  final double weightPlayProbability; //加权播放概率（0.0~1.0，阶段4 使用；展示遗留，权威已独立）
  final String lastWeightIncreaseTime; //最后增加权重时间（阶段4 使用）
  final String lastWeightDecreaseTime; //最后减少权重时间（阶段4 使用）

  const Song({
    required this.name,
    required this.audioFilePath,
    this.coverImagePath = '',
    this.lyricsFilePath = '',
    required this.addTime,
    this.duration = 0,
    this.isFavorite = false,
    required this.sortNumber,
    this.fileSize = 0,
    this.weight = 100.0,
    this.baseWeight = 100.0,
    this.weightPlayProbability = 0.0,
    this.lastWeightIncreaseTime = '',
    this.lastWeightDecreaseTime = '',
  });

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      name: json['name'] as String? ?? '',
      audioFilePath: json['audioFilePath'] as String? ?? '',
      coverImagePath: json['coverImagePath'] as String? ?? '',
      lyricsFilePath: json['lyricsFilePath'] as String? ?? '',
      addTime: json['addTime'] as String? ?? '',
      duration: (json['duration'] as num?)?.toInt() ?? 0,
      isFavorite: json['isFavorite'] as bool? ?? false,
      sortNumber: (json['sortNumber'] as num?)?.toInt() ?? 0,
      fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
      weight: (json['weight'] as num?)?.toDouble() ?? 100.0,
      baseWeight: (json['baseWeight'] as num?)?.toDouble() ?? 100.0,
      weightPlayProbability:
          (json['weightPlayProbability'] as num?)?.toDouble() ?? 0.0,
      lastWeightIncreaseTime: json['lastWeightIncreaseTime'] as String? ?? '',
      lastWeightDecreaseTime: json['lastWeightDecreaseTime'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'audioFilePath': audioFilePath,
      'coverImagePath': coverImagePath,
      'lyricsFilePath': lyricsFilePath,
      'addTime': addTime,
      'duration': duration,
      'isFavorite': isFavorite,
      'sortNumber': sortNumber,
      'fileSize': fileSize,
      'weight': double.parse(weight.toStringAsFixed(2)),
      'baseWeight': double.parse(baseWeight.toStringAsFixed(2)),
      'weightPlayProbability':
          double.parse(weightPlayProbability.toStringAsFixed(4)),
      'lastWeightIncreaseTime': lastWeightIncreaseTime,
      'lastWeightDecreaseTime': lastWeightDecreaseTime,
    };
  }

  Song copyWith({
    String? name,
    String? audioFilePath,
    String? coverImagePath,
    String? lyricsFilePath,
    String? addTime,
    int? duration,
    bool? isFavorite,
    int? sortNumber,
    int? fileSize,
    double? weight,
    double? baseWeight,
    double? weightPlayProbability,
    String? lastWeightIncreaseTime,
    String? lastWeightDecreaseTime,
  }) {
    return Song(
      name: name ?? this.name,
      audioFilePath: audioFilePath ?? this.audioFilePath,
      coverImagePath: coverImagePath ?? this.coverImagePath,
      lyricsFilePath: lyricsFilePath ?? this.lyricsFilePath,
      addTime: addTime ?? this.addTime,
      duration: duration ?? this.duration,
      isFavorite: isFavorite ?? this.isFavorite,
      sortNumber: sortNumber ?? this.sortNumber,
      fileSize: fileSize ?? this.fileSize,
      weight: weight ?? this.weight,
      baseWeight: baseWeight ?? this.baseWeight,
      weightPlayProbability: weightPlayProbability ?? this.weightPlayProbability,
      lastWeightIncreaseTime:
          lastWeightIncreaseTime ?? this.lastWeightIncreaseTime,
      lastWeightDecreaseTime:
          lastWeightDecreaseTime ?? this.lastWeightDecreaseTime,
    );
  }
}
