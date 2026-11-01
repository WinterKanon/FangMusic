/// 列表排序方式（v1.2）
///
/// 与旧的全局 [SortMode] 解耦：每个列表（主页/收藏/歌单）各自保存排序偏好，
/// 只影响该列表展示；在顺序播放模式下会同步到播放队列。
enum ListSortMode {
  addTimeAsc('添加时间正序'),
  addTimeDesc('添加时间倒序'),
  nameAsc('歌名 A-Z'),
  nameDesc('歌名 Z-A'),
  durationAsc('时长正序'),
  durationDesc('时长倒序'),
  playCountAsc('播放次数正序'),
  playCountDesc('播放次数倒序'),
  sourceOrder('默认顺序'),
  custom('自定义顺序');

  const ListSortMode(this.label);

  /// 中文标签（排序面板显示）
  final String label;

  /// 主页排序面板可用项
  static const homeOptions = [
    addTimeDesc,
    addTimeAsc,
    nameAsc,
    nameDesc,
    durationAsc,
    durationDesc,
    playCountAsc,
    playCountDesc,
  ];

  static ListSortMode fromName(String? name) {
    return ListSortMode.values.firstWhere(
      (m) => m.name == name,
      orElse: () => addTimeDesc,
    );
  }

  /// 按存储名解析（未知值回退默认值）
  static ListSortMode fromNameOrDefault(String? name, ListSortMode fallback) {
    return ListSortMode.values.firstWhere(
      (m) => m.name == name,
      orElse: () => fallback,
    );
  }
}
