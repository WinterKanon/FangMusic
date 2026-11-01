import 'package:flutter_test/flutter_test.dart';
import 'package:fs_music_app/widgets/song_selection_controller.dart';

void main() {
  test('多选：记录勾选顺序、取消、进入/退出', () {
    final c = SongSelectionController();
    c.enter();
    expect(c.isSelecting, isTrue);
    c.toggle('/a.mp3');
    c.toggle('/b.mp3');
    c.toggle('/c.mp3');
    expect(c.selectedPaths, ['/a.mp3', '/b.mp3', '/c.mp3']);
    expect(c.orderOf('/b.mp3'), 2);
    c.toggle('/b.mp3');
    expect(c.selectedPaths, ['/a.mp3', '/c.mp3']);
    expect(c.orderOf('/b.mp3'), 0);
    c.exit();
    expect(c.isSelecting, isFalse);
    expect(c.count, 0);
  });
}
