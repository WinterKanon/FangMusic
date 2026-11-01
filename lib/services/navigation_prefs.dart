import 'package:shared_preferences/shared_preferences.dart';

/// 导航偏好（v1.0 第四阶段："默认停留页面"）
///
/// - 开关：是否在下次启动时进入上次退出的页面（默认开）
/// - 记录值：`home` / `favorites` / `playlist:<id>`（仅主页、我的收藏页、
///   自定义歌单页参与记录；其他页面不覆盖记录，保留最近一次这三个页面的值）
class NavigationPrefs {
  NavigationPrefs._();

  static const _stayKey = 'stay_last_page';
  static const _pageKey = 'last_page';

  /// 读取开关（默认 true = 打开"默认停留页面"）
  static Future<bool> loadStayLastPage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_stayKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  /// 保存开关
  static Future<void> saveStayLastPage(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_stayKey, value);
    } catch (_) {
      //失败不影响使用
    }
  }

  /// 读取上次停留页面值（不存在返回 null）
  static Future<String?> loadLastPage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_pageKey);
    } catch (_) {
      return null;
    }
  }

  /// 保存停留页面值（fire-and-forget；失败不影响使用）
  static void saveLastPage(String page) {
    try {
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString(_pageKey, page);
      }).catchError((_) {});
    } catch (_) {}
  }
}
