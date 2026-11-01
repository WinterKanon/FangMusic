import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_icon_colors.dart';
import '../models/playlist.dart';
import '../models/status_colors.dart';
import '../providers/playlist_provider.dart';
import 'app_notice.dart';

/// 左侧抽屉组件（可复用）—— **三段式布局**（v1.0 第三阶段，2026-10-26 用户确认）：
///
/// - **上部**：app 用户自定义信息区（预留位置，未详细规划；第三阶段保持现状 =
///   DrawerHeader 品牌区，后续版本填充）
/// - **中部**：功能集（现有：选择音乐文件夹 / 主题色 / JSON 数据内容 / 设置 /
///   关于〔第四阶段接通页面〕；第三阶段现状不动）
/// - **下部（歌单区，可局部上下滑动）**：
///   我的收藏（**固定第一个，不可删除**）→ 自定义歌单1…N（**可删除**）→
///   新建歌单（**固定最后一个，不可删除**）；歌单**全部直接展示**（不做
///   ">5 显示前 5 个 + 更多歌单"，2026-10-26 用户取消）；
///   长按自定义歌单 → 弹 **"重命名 / 删除此歌单"** 两个选项（抽屉不退出）
///
/// 行为约定：除抽屉头外，每个可点击项点击后**自动退回抽屉**，符合直觉。
class LeftDrawerWidget extends StatelessWidget {
  const LeftDrawerWidget({
    super.key,
    required this.onScanFolder,
    this.onThemeTap,
    this.onFavoritesTap,
    this.onSettingsTap,
    this.onAboutTap,
    this.onPlaylistTap,
  });

  /// 点击"选择音乐文件夹"时回调（由主页执行完整扫描流程）
  final VoidCallback onScanFolder;

  /// 点击"主题色"时回调（主页弹出明暗 + 推荐色选择）
  final VoidCallback? onThemeTap;

  /// 点击"我的收藏"时回调（主页打开收藏页）
  final VoidCallback? onFavoritesTap;

  /// 点击"设置"时回调（主页打开设置页，v1.0）
  final VoidCallback? onSettingsTap;

  /// 点击"关于"时回调（主页打开关于页，v1.0 第四阶段）
  final VoidCallback? onAboutTap;

  /// 点击自定义歌单时回调（主页打开歌单详情页，v1.0 第三阶段）
  final void Function(Playlist playlist)? onPlaylistTap;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          //===== 上部：用户自定义信息区（预留，第三阶段保持现状） =====
          DrawerHeader(
            child: Text(
              'FangMusic',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),

          //===== 中部：功能集（现状不动） =====
          //选择音乐文件夹：退回抽屉后执行扫描流程
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: const Text('选择音乐文件夹'),
            onTap: () => _handleTap(context, onSelect: onScanFolder),
          ),
          //主题色（阶段5）
          ListTile(
            leading: const Icon(Icons.palette),
            title: const Text('主题色'),
            onTap: () => _handleTap(context, onSelect: onThemeTap),
          ),
          ListTile(
            //设置齿轮（图标色 iconSettings 可自定义）
            leading: Icon(
              Icons.settings,
              color: AppIconColors.of(context).settings,
            ),
            title: const Text('设置'),
            onTap: () => _handleTap(context, onSelect: onSettingsTap), //v1.0：打开设置页
          ),
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('关于'),
            //第四阶段实现；当前未接通时点击提示"功能还未实现"（name 兜底）
            onTap: () => _handleTap(context, onSelect: onAboutTap, name: '关于'),
            //v1.0 第四阶段：底部内边距压小 → 与分割线贴紧
            //（与"我的收藏"顶部内边距对称，两 gap 相当；不改字号）
            contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            visualDensity: VisualDensity.compact,
          ),

          //分割线：height:1 紧凑显示，"我的收藏"紧贴分割线
          //（v1.0 第四阶段优化：原来默认 height 16 导致间距过大）
          const Divider(height: 1),

          //===== 下部：歌单区（可局部上下滑动） =====
          //"我的收藏"固定第一、不可删除（系统虚拟歌单，内容 = isFavorite 动态过滤）
          Expanded(
            child: Consumer<PlaylistProvider>(
              builder: (context, playlistProvider, _) {
                final playlists = playlistProvider.playlists;
                return ListView(
                  children: [
                    //我的收藏（固定第一个，不可删除；收藏红可自定义，默认红色）
                    //字体保持默认（与"设置""关于"一致，v1.0 第四阶段）；
                    //顶部内边距压小 → 与分割线贴紧（与"关于"底部内边距对称）
                    ListTile(
                      leading: Icon(
                        Icons.favorite,
                        color: StatusColors.of(context).favoriteRed,
                      ),
                      title: const Text('我的收藏'),
                      contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                      visualDensity: VisualDensity.compact,
                      onTap: () =>
                          _handleTap(context, onSelect: onFavoritesTap),
                    ),
                    //自定义歌单1…N（可删除；长按弹"重命名/删除此歌单"）
                    for (final p in playlists)
                      ListTile(
                        leading: const Icon(Icons.playlist_play),
                        title: Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text('${p.songFilePaths.length} 首'),
                        onTap: () =>
                            _handleTap(context, onSelect: () => onPlaylistTap?.call(p)),
                        //长按：重命名 / 删除此歌单（抽屉不退出）
                        onLongPress: () =>
                            _showPlaylistActions(context, p),
                      ),
                    //新建歌单（固定最后一个，不可删除 = 创建入口）
                    ListTile(
                      leading: const Icon(Icons.add),
                      title: const Text('新建歌单'),
                      onTap: () => _showCreatePlaylistDialog(context),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  //==================== 歌单操作 ====================

  /// 长按自定义歌单 → 弹出"重命名 / 删除此歌单"两个选项（抽屉不退出）
  Future<void> _showPlaylistActions(BuildContext context, Playlist playlist) {
    return showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(height: 1),
            //重命名
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('重命名'),
              onTap: () {
                Navigator.of(ctx).pop();
                _showRenamePlaylistDialog(context, playlist);
              },
            ),
            //删除此歌单（红色警示）
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(ctx).colorScheme.error,
              ),
              title: Text(
                '删除此歌单',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _confirmDeletePlaylist(context, playlist);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 新建歌单：输入歌单名（规则校验即时提示）
  Future<void> _showCreatePlaylistDialog(BuildContext context) async {
    final name = await _promptPlaylistName(context, title: '新建歌单');
    if (name == null) return; //取消
    if (!context.mounted) return;
    context.read<PlaylistProvider>().createPlaylist(name);
    _showSnackBar(context, '已创建歌单：$name');
  }

  /// 重命名歌单：输入新歌单名（预填旧名，规则校验即时提示）
  Future<void> _showRenamePlaylistDialog(
    BuildContext context,
    Playlist playlist,
  ) async {
    final name = await _promptPlaylistName(
      context,
      title: '重命名歌单',
      initial: playlist.name,
    );
    if (name == null) return; //取消
    if (!context.mounted) return;
    context.read<PlaylistProvider>().renamePlaylist(playlist.id, name);
    _showSnackBar(context, '已重命名为：$name');
  }

  /// 歌单名输入对话框（创建/重命名共用）：
  /// - 规则：[Playlist.validateName]（非空、≤20 字、不含 `/\:*?"<>|`），
  ///   输入时即时提示错误、不允许确认
  /// - 返回 trim 后的合法名字；取消返回 null
  Future<String?> _promptPlaylistName(
    BuildContext context, {
    required String title,
    String initial = '',
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => _PlaylistNameDialog(title: title, initial: initial),
    );
  }

  /// 删除歌单确认框（抽屉不退出；确认后删除）
  Future<void> _confirmDeletePlaylist(
    BuildContext context,
    Playlist playlist,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除歌单'),
        content: Text('是否删除「${playlist.name}」歌单？\n（不会删除歌曲文件）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;
    context.read<PlaylistProvider>().deletePlaylist(playlist.id);
    _showSnackBar(context, '已删除歌单：${playlist.name}');
  }

  //==================== 工具 ====================

  /// 统一处理入口点击：先退回抽屉，再执行动作（或显示占位提示）。
  ///
  /// v1.0 第四阶段加固：关闭抽屉优先用 `Scaffold.closeDrawer()`
  /// （**不弹页面路由**）——抽屉在**子页面**（收藏页/歌单详情页）打开时，
  /// 旧逻辑 `Navigator.pop()` 会把子页面路由一并弹出（误返回）。
  /// 无宿主 Scaffold（异常兜底）才退回 `Navigator.pop()`。
  void _handleTap(
    BuildContext context, {
    VoidCallback? onSelect,
    String? name,
  }) {
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold != null) {
      scaffold.closeDrawer(); //关抽屉（不影响路由栈）
    } else {
      Navigator.of(context).pop();
    }
    if (onSelect != null) {
      onSelect();
    } else if (name != null) {
      //浮层提示（root Overlay，在抽屉/页面上层；颜色随主题）
      showAppNotice(context, '「$name」将在后续阶段实现',
          duration: const Duration(seconds: 3));
    }
  }

  void _showSnackBar(BuildContext context, String message) {
    if (!context.mounted) return;
    //抽屉内操作后的提示用浮层（root Overlay），显示在抽屉之上
    showAppNotice(context, message);
  }
}

/// 歌单名输入对话框（**独立 StatefulWidget**）
///
/// 用独立 State 而不是 StatefulBuilder + 外部 controller：TextEditingController
/// 由 State 生命周期管理，随弹窗路由（含关闭过渡动画）自然释放——
/// 规避第二阶段踩过的坑（外部 controller 提前 dispose → 弹窗反向动画期间
/// TextField 重建 → `_dependents.isEmpty` 断言崩溃）。
///
/// 返回：trim 后的合法名字；取消/关闭返回 null。
class _PlaylistNameDialog extends StatefulWidget {
  const _PlaylistNameDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<_PlaylistNameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    setState(() => _errorText = Playlist.validateName(v));
  }

  void _submit() {
    final err = Playlist.validateName(_controller.text);
    if (err != null) {
      setState(() => _errorText = err);
      return;
    }
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 20,
        decoration: InputDecoration(
          labelText: '歌单名',
          hintText: '最多 20 个字',
          errorText: _errorText,
          border: const OutlineInputBorder(),
        ),
        onChanged: _onChanged,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('确定')),
      ],
    );
  }
}
