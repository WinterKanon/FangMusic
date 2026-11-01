/// 用户歌单数据模型（纯数据，不含任何读写逻辑）
///
/// - id：唯一标识（时间戳 + 随机后缀，创建时生成）
/// - name：歌单名（规则：非空、≤20 字、不含 `/\:*?"<>|`，校验在 UI 层即时提示）
/// - createTime：创建时间（ISO 8601 字符串）
/// - songFilePaths：歌曲文件路径列表（**保持添加顺序**，即歌单播放顺序）
///
/// "我的收藏"是**系统虚拟歌单**，不是 [Playlist] 对象：
/// 它固定显示在抽屉歌单区第一位、不可删除，内容 = 全库 isFavorite 动态过滤，
/// 因此序列化文件里不会出现它。
class Playlist {
  final String id;
  final String name;
  final String createTime;
  final List<String> songFilePaths;

  const Playlist({
    required this.id,
    required this.name,
    required this.createTime,
    this.songFilePaths = const [],
  });

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      createTime: json['createTime'] as String? ?? '',
      songFilePaths:
          (json['songFilePaths'] as List? ?? [])
              .map((e) => e as String)
              .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createTime': createTime,
      'songFilePaths': songFilePaths,
    };
  }

  Playlist copyWith({String? name, List<String>? songFilePaths}) {
    return Playlist(
      id: id,
      name: name ?? this.name,
      createTime: createTime,
      songFilePaths: songFilePaths ?? this.songFilePaths,
    );
  }

  /// 歌单名是否合法：非空、≤20 字、不含 `/\:*?"<>|`
  /// （抽屉创建/重命名输入框即时校验用，规则与规划文档一致）
  static String? validateName(String input) {
    final name = input.trim();
    if (name.isEmpty) return '歌单名不能为空';
    if (name.length > 20) return '歌单名最多 20 个字';
    if (name.contains(RegExp(r'[\\/:*?"<>|]'))) {
      return '歌单名不能包含 \\ / : * ? " < > | 字符';
    }
    return null;
  }
}
