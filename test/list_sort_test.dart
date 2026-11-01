import 'package:flutter_test/flutter_test.dart';
import 'package:fs_music_app/models/list_sort_mode.dart';
import 'package:fs_music_app/models/song.dart';
import 'package:fs_music_app/services/song_sorter.dart';

/// v1.2：列表排序纯函数测试（含拼音）
void main() {
  Song song(String name, {int sort = 1, String add = '2026-01-01', int dur = 1000}) {
    return Song(
      name: name,
      audioFilePath: '/music/$name.mp3',
      sortNumber: sort,
      addTime: add,
      duration: dur,
    );
  }

  test('拼音排序：安(an) → 白(bai) → 陈(chen)，而非 Unicode 顺序', () {
    final songs = [song('陈'), song('安'), song('白')];
    final asc = SongSorter.sort(songs, ListSortMode.nameAsc);
    expect(asc.map((e) => e.name), ['安', '白', '陈']);
    final desc = SongSorter.sort(songs, ListSortMode.nameDesc);
    expect(desc.map((e) => e.name), ['陈', '白', '安']);
  });

  test('添加时间正/倒序', () {
    final songs = [
      song('a', add: '2026-01-03', sort: 3),
      song('b', add: '2026-01-01', sort: 1),
      song('c', add: '2026-01-02', sort: 2),
    ];
    expect(
      SongSorter.sort(songs, ListSortMode.addTimeAsc).map((e) => e.name),
      ['b', 'c', 'a'],
    );
    expect(
      SongSorter.sort(songs, ListSortMode.addTimeDesc).map((e) => e.name),
      ['a', 'c', 'b'],
    );
  });

  test('时长正/倒序', () {
    final songs = [
      song('short', dur: 100),
      song('long', dur: 300),
      song('mid', dur: 200),
    ];
    expect(
      SongSorter.sort(songs, ListSortMode.durationAsc).map((e) => e.name),
      ['short', 'mid', 'long'],
    );
    expect(
      SongSorter.sort(songs, ListSortMode.durationDesc).map((e) => e.name),
      ['long', 'mid', 'short'],
    );
  });

  test('播放次数排序：同次数按歌名（拼音）', () {
    final songs = [song('陈'), song('安'), song('白')];
    final counts = {
      '/music/陈.mp3': 10,
      '/music/安.mp3': 10,
      '/music/白.mp3': 5,
    };
    int countOf(String p) => counts[p] ?? 0;
    expect(
      SongSorter.sort(songs, ListSortMode.playCountAsc,
              playCountOf: countOf)
          .map((e) => e.name),
      ['白', '安', '陈'],
    );
    expect(
      SongSorter.sort(songs, ListSortMode.playCountDesc,
              playCountOf: countOf)
          .map((e) => e.name),
      ['陈', '安', '白'],
    );
  });

  test('自定义顺序：按给定路径；不在顺序中的追加末尾', () {
    final songs = [song('a'), song('b'), song('c')];
    final sorted = SongSorter.sort(
      songs,
      ListSortMode.custom,
      customOrder: ['/music/c.mp3', '/music/a.mp3'],
    );
    expect(sorted.map((e) => e.name), ['c', 'a', 'b']);
  });
}
