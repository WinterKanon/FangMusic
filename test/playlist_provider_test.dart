import 'package:flutter_test/flutter_test.dart';
import 'package:fs_music_app/models/playlist.dart';
import 'package:fs_music_app/providers/playlist_provider.dart';

/// PlaylistProvider 歌单联动测试（v1.1-2 删除歌曲：removeSongFromAllPlaylists）
void main() {
  final provider = PlaylistProvider();

  test('从所有自定义歌单移除该歌曲', () {
    provider.resetForTest(initial: [
      Playlist(
        id: 'p1',
        name: '歌单一',
        createTime: '2026-01-01T00:00:00.000',
        songFilePaths: ['/a.mp3', '/b.mp3'],
      ),
      Playlist(
        id: 'p2',
        name: '歌单二',
        createTime: '2026-01-01T00:00:00.000',
        songFilePaths: ['/a.mp3', '/c.mp3'],
      ),
    ]);
    expect(provider.removeSongFromAllPlaylists('/a.mp3'), isTrue);
    expect(provider.playlistById('p1')!.songFilePaths, ['/b.mp3']);
    expect(provider.playlistById('p2')!.songFilePaths, ['/c.mp3']);
  });

  test('幂等：歌单中本无此歌 → false 且不改变任何歌单', () {
    provider.resetForTest(initial: [
      Playlist(
        id: 'p1',
        name: '歌单一',
        createTime: '2026-01-01T00:00:00.000',
        songFilePaths: ['/b.mp3'],
      ),
    ]);
    expect(provider.removeSongFromAllPlaylists('/a.mp3'), isFalse);
    expect(provider.playlistById('p1')!.songFilePaths, ['/b.mp3']);
  });

  test('空歌单列表 → false 不崩溃', () {
    provider.resetForTest(initial: []);
    expect(provider.removeSongFromAllPlaylists('/a.mp3'), isFalse);
  });
}
