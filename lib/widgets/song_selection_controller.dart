import 'package:flutter/foundation.dart';

/// 列表多选状态（v1.2）
///
/// 记录**勾选顺序**（[selectedPaths] 按用户点击先后），供"添加下一首/加入歌单"
/// 按顺序执行；再次点击同一行取消并移出顺序。
class SongSelectionController extends ChangeNotifier {
  bool _selecting = false;
  final List<String> _paths = [];

  bool get isSelecting => _selecting;
  List<String> get selectedPaths => List.unmodifiable(_paths);
  int get count => _paths.length;
  bool contains(String path) => _paths.contains(path);

  void enter() {
    if (_selecting) return;
    _selecting = true;
    _paths.clear();
    notifyListeners();
  }

  void exit() {
    if (!_selecting && _paths.isEmpty) return;
    _selecting = false;
    _paths.clear();
    notifyListeners();
  }

  void toggle(String path) {
    final i = _paths.indexOf(path);
    if (i >= 0) {
      _paths.removeAt(i);
    } else {
      _paths.add(path);
    }
    notifyListeners();
  }

  void clear() {
    if (_paths.isEmpty) return;
    _paths.clear();
    notifyListeners();
  }

  /// 勾选序号（从 1 开始；不在选中列表返回 0）
  int orderOf(String path) => _paths.indexOf(path) + 1;
}
