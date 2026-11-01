import 'package:pinyin/pinyin.dart';

import '../models/list_sort_mode.dart';
import '../models/song.dart';

/// 列表排序纯函数（v1.2）
///
/// 统一处理主页/收藏/歌单的展示排序，避免各页面各写一套比较逻辑。
/// - 预设排序：添加时间 / 歌名（拼音）/ 时长 / 播放次数；
/// - `sourceOrder`：保持传入顺序（收藏/歌单默认）；
/// - `custom`：按自定义路径顺序，未在顺序中的歌曲追加到末尾。
class SongSorter {
  /// 排序（返回新列表，不修改入参）
  static List<Song> sort(
    List<Song> songs,
    ListSortMode mode, {
    List<String> customOrder = const [],
    int Function(String path)? playCountOf,
  }) {
    final list = List<Song>.of(songs);
    if (mode == ListSortMode.sourceOrder) return list;
    if (mode == ListSortMode.custom) {
      return _applyCustomOrder(list, customOrder);
    }
    //装饰原索引，保证完全相同的排序键也保持稳定顺序
    final decorated = [
      for (var i = 0; i < list.length; i++) (song: list[i], index: i),
    ];
    decorated.sort((a, b) {
      final c = _compare(a.song, b.song, mode, playCountOf);
      if (c != 0) return c;
      return a.index.compareTo(b.index);
    });
    return [for (final e in decorated) e.song];
  }

  static List<Song> _applyCustomOrder(
      List<Song> songs, List<String> customOrder) {
    final indexOf = <String, int>{
      for (var i = 0; i < customOrder.length; i++) customOrder[i]: i,
    };
    final decorated = [
      for (var i = 0; i < songs.length; i++)
        (song: songs[i], order: indexOf[songs[i].audioFilePath], index: i),
    ];
    decorated.sort((a, b) {
      final ao = a.order, bo = b.order;
      if (ao == null && bo == null) return a.index.compareTo(b.index);
      if (ao == null) return 1; //未在自定义顺序中的排最后
      if (bo == null) return -1;
      return ao.compareTo(bo);
    });
    return [for (final e in decorated) e.song];
  }

  static int _compare(
    Song a,
    Song b,
    ListSortMode mode,
    int Function(String path)? playCountOf,
  ) {
    switch (mode) {
      case ListSortMode.addTimeAsc:
        final c = a.addTime.compareTo(b.addTime);
        return c != 0 ? c : a.sortNumber.compareTo(b.sortNumber);
      case ListSortMode.addTimeDesc:
        final c = b.addTime.compareTo(a.addTime);
        //同一批扫描导入的歌曲 addTime 相同：用 sortNumber 倒序兜底，
        //保证"倒序"至少是导入顺序的反向（否则看起来排序无效）
        return c != 0 ? c : b.sortNumber.compareTo(a.sortNumber);
      case ListSortMode.nameAsc:
        return _compareName(a, b, asc: true);
      case ListSortMode.nameDesc:
        return _compareName(a, b, asc: false);
      case ListSortMode.durationAsc:
        final c = a.duration.compareTo(b.duration);
        return c != 0 ? c : a.sortNumber.compareTo(b.sortNumber);
      case ListSortMode.durationDesc:
        final c = b.duration.compareTo(a.duration);
        return c != 0 ? c : a.sortNumber.compareTo(b.sortNumber);
      case ListSortMode.playCountAsc:
        final ca = playCountOf?.call(a.audioFilePath) ?? 0;
        final cb = playCountOf?.call(b.audioFilePath) ?? 0;
        final c = ca.compareTo(cb);
        return c != 0 ? c : _compareName(a, b, asc: true);
      case ListSortMode.playCountDesc:
        final ca = playCountOf?.call(a.audioFilePath) ?? 0;
        final cb = playCountOf?.call(b.audioFilePath) ?? 0;
        final c = cb.compareTo(ca);
        return c != 0 ? c : _compareName(a, b, asc: false);
      case ListSortMode.sourceOrder:
      case ListSortMode.custom:
        return 0;
    }
  }

  static int _compareName(Song a, Song b, {required bool asc}) {
    final ka = pinyinKey(a.name), kb = pinyinKey(b.name);
    final c = asc ? ka.compareTo(kb) : kb.compareTo(ka);
    if (c != 0) return c;
    //拼音相同：回退原歌名，保证稳定
    final raw = asc ? a.name.compareTo(b.name) : b.name.compareTo(a.name);
    if (raw != 0) return raw;
    return a.sortNumber.compareTo(b.sortNumber);
  }

  static final Map<String, String> _pinyinCache = {};

  /// 歌名排序 key：中文转小写无声调拼音，英文/数字保留并转小写。
  /// 转换失败/非中文原样保留；结果按歌名缓存。
  static String pinyinKey(String name) {
    final cached = _pinyinCache[name];
    if (cached != null) return cached;
    final sb = StringBuffer();
    for (final rune in name.runes) {
      final ch = String.fromCharCode(rune);
      if (ChineseHelper.isChinese(ch)) {
        try {
          sb.write(PinyinHelper.getPinyin(
            ch,
            separator: '',
            format: PinyinFormat.WITHOUT_TONE,
          ).toLowerCase());
        } catch (_) {
          sb.write(ch);
        }
      } else {
        sb.write(ch.toLowerCase());
      }
    }
    final key = sb.toString().trim();
    final result = key.isEmpty ? name.toLowerCase() : key;
    _pinyinCache[name] = result;
    return result;
  }

  /// 测试用：清空拼音缓存
  static void clearCache() => _pinyinCache.clear();
}
