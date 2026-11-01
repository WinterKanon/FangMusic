/// 已选择的音乐文件夹（v1.1-5）
///
/// 用户每次通过抽屉"选择音乐文件夹"导入一个文件夹，都会记录在这里，
/// 供"设置 → 所选文件夹管理"查看/移除；移除只影响 app 内的歌曲，不删除文件。
class MusicFolder {
  const MusicFolder({
    required this.path,
    required this.name,
    required this.addedAt,
  });

  /// 文件夹绝对路径（扫描得到，如 /storage/emulated/0/Music）
  final String path;

  /// 文件夹名（取路径最后一段，用于列表展示）
  final String name;

  /// 添加时间（ISO8601，用于排序）
  final String addedAt;

  MusicFolder copyWith({String? path, String? name, String? addedAt}) {
    return MusicFolder(
      path: path ?? this.path,
      name: name ?? this.name,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'addedAt': addedAt,
      };

  factory MusicFolder.fromJson(Map<String, dynamic> json) {
    final path = (json['path'] as String?) ?? '';
    return MusicFolder(
      path: path,
      name: (json['name'] as String?) ?? path.split('/').last,
      addedAt: (json['addedAt'] as String?) ?? '',
    );
  }
}
