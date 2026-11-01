import 'package:shared_preferences/shared_preferences.dart';

/// 列表排序方式（阶段5）
///
/// - addTime 添加时间：按歌曲导入时间升序（默认，现状即此顺序）
/// - name 歌名：按歌名排序（中文按 Unicode 码点序，未引入拼音库）
/// - duration 时长：按时长升序
///
/// 选择排序方式后：列表重排 + **重写 sortNumber(1..n)** + 写库 +
/// 持久化偏好（顺序播放队列跟随新顺序）。
enum SortMode {
  addTime('添加时间'),
  name('歌名'),
  duration('时长');

  const SortMode(this.label);

  /// 中文标签（排序菜单显示）
  final String label;

  static const _prefKey = 'sort_mode';

  /// 从偏好读取当前排序方式（默认添加时间；读取失败也回退默认）
  static Future<SortMode> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return fromName(prefs.getString(_prefKey));
    } catch (_) {
      return SortMode.addTime;
    }
  }

  /// 按存储名解析（未知值回退添加时间）
  static SortMode fromName(String? name) {
    return SortMode.values.firstWhere(
      (m) => m.name == name,
      orElse: () => SortMode.addTime,
    );
  }

  /// 持久化当前排序方式
  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      //注意：用 this.name（Enum.name），避免与同名枚举值 SortMode.name 冲突
      await prefs.setString(_prefKey, this.name);
    } catch (_) {
      //偏好写入失败不影响使用
    }
  }
}
