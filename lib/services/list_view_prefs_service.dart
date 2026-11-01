import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/list_sort_mode.dart';
import 'storage_service.dart';

/// 单个列表的展示偏好
class ListViewPref {
  ListSortMode sort;
  List<String> customOrder;

  ListViewPref({
    required this.sort,
    List<String>? customOrder,
  }) : customOrder = List<String>.of(customOrder ?? const []);

  Map<String, dynamic> toJson() => {
        'sort': sort.name,
        'customOrder': customOrder,
      };

  factory ListViewPref.fromJson(Map<String, dynamic> json,
      ListSortMode fallback) {
    final order = (json['customOrder'] as List?)
            ?.map((e) => e as String)
            .toList() ??
        <String>[];
    return ListViewPref(
      sort: ListSortMode.fromNameOrDefault(json['sort'] as String?, fallback),
      customOrder: order,
    );
  }
}

/// 列表展示偏好服务（v1.2）
///
/// 每个列表 Key 保存：排序方式 + 自定义顺序；落 `list_view_database.json`
/// （`StorageService` 原子写/.bak）。页面不直接读写文件。
class ListViewPrefsService extends ChangeNotifier {
  static final ListViewPrefsService instance = ListViewPrefsService._();
  ListViewPrefsService._();

  static const String keyHome = 'home';
  static const String keyFavorites = 'favorites';
  static String keyForPlaylist(String id) => 'playlist:$id';

  final Map<String, ListViewPref> _prefs = {};
  bool _loaded = false;

  bool get isLoaded => _loaded;

  /// 默认排序：主页添加时间倒序；收藏/歌单默认来源顺序
  ListSortMode defaultSortFor(String key) =>
      key == keyHome ? ListSortMode.addTimeDesc : ListSortMode.sourceOrder;

  ListSortMode sortFor(String key) =>
      _prefs[key]?.sort ?? defaultSortFor(key);

  List<String> customOrderFor(String key) =>
      List.unmodifiable(_prefs[key]?.customOrder ?? const <String>[]);

  ListViewPref prefFor(String key) => _prefs.putIfAbsent(
      key, () => ListViewPref(sort: defaultSortFor(key)));

  /// 加载偏好（幂等）；首次加载时迁移旧 `sort_mode` 偏好
  Future<void> load() async {
    if (_loaded) return;
    final data = await StorageService.loadListViewPrefs();
    if (data != null) {
      final lists = data['lists'];
      if (lists is Map<String, dynamic>) {
        for (final entry in lists.entries) {
          final value = entry.value;
          if (value is Map<String, dynamic>) {
            _prefs[entry.key] =
                ListViewPref.fromJson(value, defaultSortFor(entry.key));
          }
        }
      }
    }
    //旧版本排序偏好迁移（只对主页；addTime 默认值映射到新的倒序默认）
    if (!_prefs.containsKey(keyHome)) {
      final old = await _loadOldSortMode();
      final mode = switch (old) {
        'name' => ListSortMode.nameAsc,
        'duration' => ListSortMode.durationAsc,
        _ => ListSortMode.addTimeDesc,
      };
      _prefs[keyHome] = ListViewPref(sort: mode);
      await _save();
    } else if (data == null) {
      await _save();
    }
    _prefs.putIfAbsent(
        keyFavorites, () => ListViewPref(sort: ListSortMode.sourceOrder));
    _loaded = true;
    notifyListeners();
  }

  Future<String?> _loadOldSortMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('sort_mode');
    } catch (_) {
      return null;
    }
  }

  Future<void> setSort(String key, ListSortMode mode) async {
    final pref = prefFor(key);
    if (pref.sort == mode) return;
    pref.sort = mode;
    notifyListeners();
    await _save();
  }

  Future<void> setCustomOrder(String key, List<String> order) async {
    final pref = prefFor(key);
    pref
      ..sort = ListSortMode.custom
      ..customOrder = List<String>.of(order);
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    await StorageService.saveListViewPrefs({
      'lists': {
        for (final e in _prefs.entries) e.key: e.value.toJson(),
      },
    });
  }

  @visibleForTesting
  void resetForTest() {
    _prefs.clear();
    _loaded = false;
  }
}
