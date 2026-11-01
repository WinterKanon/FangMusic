import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/app_icon_colors.dart';
import '../models/theme_palette.dart';
import '../providers/theme_provider.dart';
import '../services/storage_service.dart';
import '../widgets/app_background.dart';

/// JSON 调试页（阶段6）：
/// 只读展示三个数据库文件的**原始 JSON 内容**（不经解析、保持原样），
/// 便于核对权重、收藏、排序号、歌单等字段的实际落盘值。
///
/// - 顶部：文件切换（歌曲库 / 播放队列 / 歌单库）+ 刷新 + 复制
/// - 内容：等宽字体 SelectableText，可长按选择复制
/// - 空态：文件尚未创建时给出引导（还没扫描过歌曲/还没生成队列/还没创建歌单）
///
/// [songsReader] / [tasksReader] / [playlistsReader] 仅供测试注入，
/// 生产默认走 [StorageService]。
class JsonDataPage extends StatefulWidget {
  const JsonDataPage({
    super.key,
    this.songsReader,
    this.tasksReader,
    this.playlistsReader,
  });

  /// 测试注入：读取歌曲库原始文本；null 时用 StorageService 默认
  final Future<String?> Function()? songsReader;

  /// 测试注入：读取播放队列原始文本；null 时用 StorageService 默认
  final Future<String?> Function()? tasksReader;

  /// 测试注入：读取歌单库原始文本；null 时用 StorageService 默认（v1.0 第三阶段）
  final Future<String?> Function()? playlistsReader;

  @override
  State<JsonDataPage> createState() => _JsonDataPageState();
}

/// 三个可查看的数据文件
enum _JsonTarget { songs, playTasks, playlists }

class _JsonDataPageState extends State<JsonDataPage> {
  _JsonTarget _target = _JsonTarget.songs;
  String? _content; //null = 正在加载/尚未加载
  bool _loading = false;
  final TextEditingController _controller = TextEditingController();
  String? _searchTerm; //当前搜索关键词；null = 未搜索（v1.0 第四阶段：查找）
  int _searchIndex = 0; //当前选中的匹配序号（0-based，配合"上/下"切换）

  //v1.0 第四阶段（用户 2026-10-27）：按行渲染 + 选中匹配自动滚动到屏幕中。
  //v1.1-3 修复：整页 Column 一次性布局几千行 SelectableText 导致滑动卡顿 →
  //改 ListView.builder 懒加载（itemExtent 固定行高），滑动只构建可见行。
  final ScrollController _contentScroll = ScrollController();
  /// 单行固定高度（monospace 12 + height 2.0 = 24px；与列表 itemExtent 一致）。
  /// v1.1-3（用户 2026-10-29）：行距拉开到约原 1.33 倍（要求 1.2~1.5）
  static const double _lineHeight = 24.0;
  List<int> _matchLineByIndex = []; //全局第 k 个匹配所在行号
  List<int> _lineMatchStart = []; //第 i 行的第一个匹配的全局序号

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 读取当前目标文件的原始内容
  Future<void> _load() async {
    setState(() => _loading = true);
    final raw = switch (_target) {
      _JsonTarget.songs => await (widget.songsReader ?? StorageService.readSongsRaw)(),
      _JsonTarget.playTasks =>
        await (widget.tasksReader ?? StorageService.readPlayTasksRaw)(),
      _JsonTarget.playlists =>
        await (widget.playlistsReader ?? StorageService.readPlaylistsRaw)(),
    };
    if (!mounted) return;
    setState(() {
      _content = raw;
      _loading = false;
    });
  }

  void _switchTarget(_JsonTarget t) {
    if (t == _target) return;
    setState(() => _target = t);
    _load();
  }

  Future<void> _copy() async {
    final content = _content;
    if (content == null) return;
    await Clipboard.setData(ClipboardData(text: content));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
  }

  /// 搜索按钮：已有搜索词 → 清除；否则弹输入框（相当于"查找"）
  Future<void> _onSearchPressed() async {
    if (_searchTerm != null) {
      setState(() {
        _searchTerm = null;
        _searchIndex = 0;
        _matchLineByIndex = [];
        _lineMatchStart = [];
      });
      return;
    }
    final term = await _promptSearchTerm();
    if (term == null) return; //取消
    if (!mounted) return;
    final content = _content;
    if (content == null) return;
    setState(() {
      //空关键词等同清除；否则大小写不敏感查找
      _searchTerm = term.trim().isEmpty ? null : term.trim();
      _searchIndex = 0; //新查找从第一个匹配开始选中
      _rebuildMatchIndex();
    });
    //新搜索后：选中的第一个匹配自动滚动到屏幕中
    WidgetsBinding.instance.addPostFrameCallback((_) => _gotoSelectedMatch());
  }

  /// 搜索关键词输入对话框：返回 trim 后的关键词；取消返回 null。
  /// [initialValue] 非空时预填（点击浮窗关键词"编辑原关键词"场景）
  Future<String?> _promptSearchTerm({String? initialValue}) {
    return showDialog<String>(
      context: context,
      builder: (_) => _SearchTermDialog(initialValue: initialValue),
    );
  }

  String get _title => switch (_target) {
        _JsonTarget.songs => '歌曲库 JSON',
        _JsonTarget.playTasks => '播放队列 JSON',
        _JsonTarget.playlists => '歌单库 JSON',
      };

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        //页面级背景（补充 17）：背景 + 遮罩在 Scaffold 之下，页面出现即带背景
        const AppBackground(pageKey: ThemePalette.pageKeyJsonData),
        Scaffold(
      appBar: AppBar(
        title: Text(_title),
        centerTitle: true,
        actions: [
          //刷新
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
          //搜索（查找）：刷新与复制之间（v1.0 第四阶段）
          IconButton(
            tooltip: _searchTerm == null ? '搜索内容' : '清除搜索',
            icon: Icon(_searchTerm == null ? Icons.search : Icons.close),
            onPressed: _onSearchPressed,
          ),
          //复制
          IconButton(
            tooltip: '复制',
            icon: const Icon(Icons.copy),
            onPressed: _copy,
          ),
        ],
      ),
      //顶部文件切换（SegmentedButton；tab 图标色跟随 iconQueue 可自定义）。
      //v1.0 第四阶段：搜索态在 Tab 栏下方右侧叠加"查找弹窗"（<num>/<max>
      //+ 上/下切换选中匹配，颜色用 jsonSearchBg/jsonSearchText 自定义）
      body: Stack(
        children: [
          Column(
            children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<_JsonTarget>(
              segments: [
                ButtonSegment(
                  value: _JsonTarget.songs,
                  icon: Icon(
                    Icons.library_music,
                    color: AppIconColors.of(context).queue,
                  ),
                  label: const Text('歌曲库'),
                ),
                ButtonSegment(
                  value: _JsonTarget.playTasks,
                  icon: Icon(
                    Icons.playlist_play,
                    color: AppIconColors.of(context).queue,
                  ),
                  label: const Text('播放队列'),
                ),
                ButtonSegment(
                  value: _JsonTarget.playlists,
                  icon: Icon(
                    Icons.queue_music,
                    color: AppIconColors.of(context).queue,
                  ),
                  label: const Text('歌单库'),
                ),
              ],
              selected: {_target},
              onSelectionChanged: (s) => _switchTarget(s.first),
            ),
          ),
          Expanded(child: _buildContent()),
            ],
          ),
          if (_searchTerm != null) _buildSearchFloater(context),
        ],
      ),
      ),
    ],
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final content = _content;
    if (content == null) {
      //文件不存在
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_off,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            const Text('文件尚未创建', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              switch (_target) {
                _JsonTarget.songs =>
                  '还没有扫描过歌曲\n扫描文件夹后会自动生成歌曲库文件',
                _JsonTarget.playTasks =>
                  '还没有生成播放队列\n播放过歌曲后会自动生成队列文件',
                _JsonTarget.playlists =>
                  '还没有创建歌单\n在抽屉底部点击"新建歌单"后会生成歌单库文件',
              },
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    //只读 + 等宽字体 + 可选中复制。v1.0 第四阶段：按行渲染 + 搜索高亮
    //（一级 = 所有匹配 / 二级 = 当前选中）。
    //v1.1-3 性能修复：**ListView.builder 懒加载**（itemExtent 固定行高），
    //大 JSON（几千行）不再一次性布局全部行 → 滑动流畅；
    //每行 maxLines:1 不换行（超长行右侧截断，可用搜索/复制获取完整内容）。
    final lines = content.split('\n');
    return ListView.builder(
      controller: _contentScroll,
      padding: const EdgeInsets.all(12),
      itemExtent: _lineHeight,
      itemCount: lines.length,
      itemBuilder: (context, i) => SelectableText.rich(
        _buildLineSpan(lines[i], i),
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          height: 2.0, //行距拉开（与 itemExtent 24px 对应）
        ),
        maxLines: 1, //单行截断（SelectableText 无 softWrap，默认即不换行）
      ),
    );
  }

  /// 查找弹窗（v1.0 第四阶段补全）：显示 "<当前序号>/<总数>" + 上/下按钮，
  /// 点击切换选中的匹配（循环切换）。位置：Tab 栏下方、屏幕右上角。
  /// 配色：背景/文字用"栏与弹窗 → JSON 查找背景/文字"自定义，
  /// 默认 日间白/夜间黑 背景 + 主题色文字；边框用强调色（主题色）。
  Widget _buildSearchFloater(BuildContext context) {
    final theme = context.read<ThemeProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final count = _matchLineByIndex.length;
    final bg = theme.palette.colorOf(PaletteItem.jsonSearchBg);
    final fg = theme.palette.colorOf(PaletteItem.jsonSearchText);
    final bgColor = bg != null ? Color(bg) : (isDark ? Colors.black : Colors.white);
    final fgColor = fg != null
        ? Color(fg)
        : (theme.isDefaultPreset
            ? ThemeProvider.kDefaultHighlightBlue
            : theme.seedColor(isDark));
    return Positioned(
      //位置（v1.0 第四阶段，用户 2026-10-27 调整）：Tab 栏**下面**、靠右
      top: 68,
      right: 12,
      child: Material(
        color: bgColor,
        elevation: 4,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: theme.seedColor(isDark), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              //a. 查找的关键词（如 name；超长截断），外包主题色细线框。
              //v1.1-3（用户 2026-10-29）：点击关键词可重新输入新的查找词
              Flexible(
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: _onKeywordTapped,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: theme.seedColor(isDark), width: 1),
                    ),
                    child: Text(
                      _searchTerm!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fgColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              //b. <num>/<max>
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '${count <= 0 ? 0 : _searchIndex + 1}/$count',
                  style: TextStyle(
                    color: fgColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              //c. 上一个（循环切换）
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () {
                  if (count <= 0) return;
                  setState(() {
                    _searchIndex = (_searchIndex - 1 + count) % count;
                  });
                  WidgetsBinding.instance
                      .addPostFrameCallback((_) => _gotoSelectedMatch());
                },
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(Icons.keyboard_arrow_up, size: 20, color: fgColor),
                ),
              ),
              //d. 下一个（循环切换）
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () {
                  if (count <= 0) return;
                  setState(() {
                    _searchIndex = (_searchIndex + 1) % count;
                  });
                  WidgetsBinding.instance
                      .addPostFrameCallback((_) => _gotoSelectedMatch());
                },
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(Icons.keyboard_arrow_down, size: 20, color: fgColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建单行文本的富文本（v1.0 第四阶段，用户 2026-10-27 调整）。
  /// v1.1-3（用户 2026-10-29 拍板）：一级/二级高亮**统一**配色——
  /// 背景默认 = 主题色（强调与图标 → 主题色）、文字默认 = 主题色反色；
  /// 二者默认相同（解决此前"一级二级谁更明显"的设计冲突），
  /// 可分别在"强调与图标 → JSON 一级/二级高亮关键词背景/文字"自定义。
  TextSpan _buildLineSpan(String line, int lineIndex) {
    final theme = context.read<ThemeProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = theme.seedColor(isDark);
    Color hlBg(PaletteItem bg) {
      final v = theme.palette.colorOf(bg);
      return v != null ? Color(v) : accent;
    }

    Color hlFg(PaletteItem fg) {
      final v = theme.palette.colorOf(fg);
      return v != null
          ? Color(v)
          : (accent.computeLuminance() > 0.5 ? Colors.black : Colors.white);
    }

    final term = _searchTerm;
    if (term == null || term.isEmpty) return TextSpan(text: line);
    final lower = line.toLowerCase();
    final t = term.toLowerCase();
    final spans = <TextSpan>[];
    var c = 0; //行内匹配序号（0-based）
    var start = 0;
    while (true) {
      final idx = lower.indexOf(t, start);
      if (idx < 0) {
        if (start < line.length) {
          spans.add(TextSpan(text: line.substring(start)));
        }
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: line.substring(start, idx)));
      }
      final isSelected = lineIndex < _lineMatchStart.length &&
          (_lineMatchStart[lineIndex] + c) == _searchIndex;
      spans.add(
        TextSpan(
          text: line.substring(idx, idx + t.length),
          style: isSelected
              //二级（当前选中的匹配）：二级高亮背景/文字
              ? TextStyle(
                  backgroundColor: hlBg(PaletteItem.jsonHighlight2Bg),
                  color: hlFg(PaletteItem.jsonHighlight2Text),
                  fontWeight: FontWeight.bold,
                )
              //一级（所有匹配）：一级高亮背景/文字
              : TextStyle(
                  backgroundColor: hlBg(PaletteItem.jsonHighlight1Bg),
                  color: hlFg(PaletteItem.jsonHighlight1Text),
                  fontWeight: FontWeight.bold,
                ),
        ),
      );
      c++;
      start = idx + t.length;
    }
    return TextSpan(children: spans);
  }

  /// v1.1-3（用户 2026-10-29）：点击查找弹窗中的关键词 → 重新输入新的查找词
  /// （复用搜索对话框；输入空 = 清除搜索）
  Future<void> _onKeywordTapped() async {
    //v1.1-3（用户 2026-10-29）：预填当前关键词，用户直接修改而非重新输入
    final term = await _promptSearchTerm(initialValue: _searchTerm);
    if (term == null) return; //取消
    if (!mounted) return;
    final content = _content;
    if (content == null) return;
    setState(() {
      _searchTerm = term.trim().isEmpty ? null : term.trim();
      _searchIndex = 0;
      _rebuildMatchIndex();
    });
    if (_searchTerm != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _gotoSelectedMatch());
    }
  }

  /// 重建"全局匹配序号 → 行号"索引与每行匹配起始序号
  /// （搜索词设置/清除时调用；上/下切换不改变索引）
  void _rebuildMatchIndex() {
    _matchLineByIndex = [];
    final content = _content;
    final term = _searchTerm;
    if (content == null || term == null || term.isEmpty) {
      _lineMatchStart = [];
      return;
    }
    final lines = content.split('\n');
    _lineMatchStart = List.filled(lines.length, 0);
    final t = term.toLowerCase();
    var g = 0; //全局匹配序号
    for (var i = 0; i < lines.length; i++) {
      _lineMatchStart[i] = g;
      final lower = lines[i].toLowerCase();
      var idx = lower.indexOf(t);
      while (idx >= 0) {
        _matchLineByIndex.add(i);
        g++;
        idx = lower.indexOf(t, idx + t.length);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _contentScroll.dispose();
    super.dispose();
  }

  /// 将"当前选中的匹配"所在行滚动到屏幕中（上/下切换后调用）：
  /// 懒加载 ListView 下行 widget 可能尚未构建（无 context），
  /// 直接按"行号 × 行高"jumpTo 定位。
  /// v1.1-3（用户 2026-10-29）：目标行出现在**屏幕中部偏上**
  /// （黄金分割比例 0.382 × 视口高度）处，而非视口顶部。
  void _gotoSelectedMatch() {
    if (_matchLineByIndex.isEmpty) return;
    final idx = _searchIndex.clamp(0, _matchLineByIndex.length - 1);
    final line = _matchLineByIndex[idx];
    if (line < 0) return;
    final viewport = _contentScroll.position.viewportDimension;
    //黄金分割位：让目标行顶端对齐到视口自上而下 38.2% 处
    final target = line * _lineHeight - viewport * 0.382;
    _contentScroll.jumpTo(target < 0 ? 0 : target);
  }


}

/// 搜索关键词输入对话框（JSON 页"查找"）：返回 trim 后的关键词；取消返回 null。
/// v1.1-3（用户 2026-10-29）：[initialValue] 非空时预填（编辑原关键词场景）
class _SearchTermDialog extends StatefulWidget {
  const _SearchTermDialog({this.initialValue});

  final String? initialValue;

  @override
  State<_SearchTermDialog> createState() => _SearchTermDialogState();
}

class _SearchTermDialogState extends State<_SearchTermDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    //预填场景：光标移到末尾，用户可直接追加字符或全选重改
    final init = widget.initialValue;
    if (init != null && init.isNotEmpty) {
      _controller.selection =
          TextSelection.collapsed(offset: _controller.text.length);
    }
    return AlertDialog(
      title: const Text('搜索 JSON 内容'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: '关键词',
          hintText: '输入要查找的内容（不区分大小写）',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('查找')),
      ],
    );
  }
}
