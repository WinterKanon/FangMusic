import 'package:flutter/material.dart';

import '../models/theme_palette.dart';
import '../widgets/app_background.dart';

/// "使用介绍"页（v1.0 第四阶段）
///
/// 从"设置 → 关于"进入。按功能分组介绍 app 的玩法与细节、注意事项。
/// 布局与其余页面一致：页面级背景 + 透明 AppBar + ListView。
class UsageGuidePage extends StatelessWidget {
  const UsageGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const AppBackground(pageKey: ThemePalette.pageKeySettingsPages),
        Scaffold(
          appBar: AppBar(title: const Text('使用介绍'), centerTitle: true),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              const _Section(title: '播放模式', icon: Icons.play_circle_outline, children: [
                _Item(
                  title: '顺序播放',
                  desc: '按列表顺序播放，播完最后一首后回到第一首（首尾循环）。',
                  tips: '切换进度可通过底部播放栏拖动；播放中切换模式不会打断当前歌曲。',
                ),
                _Item(
                  title: '单曲循环',
                  desc: '当前歌曲播完后从头重复播放同一首，不会自动切到下一首。',
                  tips: '此模式下通知栏与锁屏仍有"上一首 / 下一首"，点击后仍播放这首歌。',
                ),
                _Item(
                  title: '普通随机',
                  desc: '随机打乱播放，首批 50 首 + 滑动窗口补充，保证播放不重复、不枯竭。',
                  tips: '随机是"整批生成"的，通知栏切歌也遵循同一份随机队列。',
                ),
                _Item(
                  title: '加权随机',
                  desc: '按每首歌的权重值决定被随机选中的概率（权重越高越容易被播放）。',
                  tips: '权重受各种操作影响（见"权重调节"）；概率会随权重变化实时重算。',
                ),
              ]),
              const _Section(
                  title: '列表信息栏与排序',
                  icon: Icons.sort,
                  children: [
                _Item(
                  title: '信息栏',
                  desc: '主页/收藏/歌单页顶部信息栏显示播放模式、歌曲数、排序方式与多选入口。',
                ),
                _Item(
                  title: '排序方式',
                  desc: '支持添加时间、歌名（中文按拼音 A-Z/Z-A）、时长、播放次数与自定义顺序。',
                  tips: '顺序播放时，主页/收藏/歌单的排序会同步重排播放队列；'
                      '若正在播放，当前歌与进度保持不变。',
                ),
                _Item(
                  title: '手动点歌与队列',
                  desc: '顺序模式下手动点非当前歌时，会以点击歌为首重排队列；'
                      '“下一首”任务按原顺序紧随其后。',
                ),
              ]),
              const _Section(
                  title: '多选与批量操作',
                  icon: Icons.checklist,
                  children: [
                _Item(
                  title: '进入多选',
                  desc: '点击信息栏右侧多选图标；勾选歌曲会显示顺序。多选时长按歌曲可拖动排序。',
                ),
                _Item(
                  title: '仅移除库',
                  desc: '从 app 移除并清理收藏/歌单/队列关系，保留权重、播放次数与本地文件；'
                      '下拉刷新会重新出现。',
                ),
                _Item(
                  title: '永久删除',
                  desc: '删除本地文件并清理全部关联数据（不可恢复）；Android 11+ 需一次文件权限。',
                ),
                _Item(
                  title: '加入歌单 / 添加下一首',
                  desc: '按勾选顺序去重加入歌单，或依次插入当前歌之后。',
                ),
              ]),
              const _Section(
                  title: '播放界面与睡眠定时',
                  icon: Icons.bedtime_outlined,
                  children: [
                _Item(
                  title: '播放界面页',
                  desc: '点击底部播放栏封面或歌名进入；可拖动进度、切歌，'
                      '底部提供模式/倍速/睡眠/更多/队列入口。',
                  tips: '“更多”等同当前歌曲长按菜单；倍速支持 0.25x-5x 与自定义；'
                      '歌词区域暂为占位。',
                ),
                _Item(
                  title: '睡眠定时',
                  desc: '可选 15/30/45/60/90 分钟或输入 1-120 分钟；'
                      '结束方式为“立即暂停”或“播完当前歌曲再暂停”。',
                  tips: '到点后手动切歌/暂停会取消待暂停；到点已暂停则定时直接结束。',
                ),
              ]),
              const _Section(title: '权重调节', icon: Icons.tune, children: [
                _Item(
                  title: '手动点击',
                  desc: '手动点击播放某首歌会立即增加权重（默认 +30，可在'
                      '"设置 → 权重调节页"修改）。',
                ),
                _Item(
                  title: '事件调权',
                  desc: '收藏（+200）、添加下一首（+100）、搜索播放（+15）、单曲循环、'
                      '10 秒内快切（-）、完整播完（+）等操作都会影响权重。',
                ),
                _Item(
                  title: '播放衰减与回归',
                  desc: '连续被随机播放时权重逐次衰减（前 4 次），7 天后未被播放的歌曲'
                      '权重会回归，避免冷门歌永远不被播放。',
                ),
                _Item(
                  title: '权重范围',
                  desc: '在"设置 → 权重调节页"可设置权重的上下限；长按歌曲可单独查看'
                      '并手动设置某首歌的权重。',
                  tips: '修改"调权数值"后记得点击"保存设置"才会生效。',
                ),
              ]),
              const _Section(title: '收藏与收藏页', icon: Icons.star_outline, children: [
                _Item(
                  title: '收藏',
                  desc: '在歌曲行尾点击星形图标（或长按歌曲 → 收藏）即可收藏，'
                      '收藏后权重 +200。',
                ),
                _Item(
                  title: '收藏页',
                  desc: '抽屉底部"我的收藏"进入，展示全部收藏歌曲；点击可播放，'
                      '再次点击星形取消收藏（权重 -100）。',
                ),
              ]),
              const _Section(title: '自定义歌单', icon: Icons.playlist_play, children: [
                _Item(
                  title: '新建歌单',
                  desc: '抽屉底部"新建歌单"创建；输入名称即可。',
                ),
                _Item(
                  title: '重命名 / 删除',
                  desc: '在抽屉中长按歌单弹出"重命名 / 删除此歌单"。',
                ),
                _Item(
                  title: '批量加入歌单',
                  desc: '歌单详情页（或长按歌曲菜单）可把多首歌曲批量加入指定歌单。',
                  tips: '"我的收藏"固定第一个不可删除；自定义歌单可删除。',
                ),
              ]),
              const _Section(title: '添加下一首', icon: Icons.playlist_add, children: [
                _Item(
                  title: '用法',
                  desc: '歌曲行尾的"添加下一首"图标（或长按歌曲菜单）把该歌插入到'
                      '当前播放歌曲之后，播放完当前歌后接着播。',
                  tips: '可以连续标记多首；通知栏 / 锁屏"下一首"与 app 内切歌遵循同一队列，'
                      '顺序完全一致。',
                ),
              ]),
              const _Section(title: '悬浮定位按钮', icon: Icons.my_location, children: [
                _Item(
                  title: '作用',
                  desc: '主页、收藏页、歌单页右下角的定位按钮：一键把正在播放的歌曲'
                      '（高亮）滚动到屏幕中部偏上，省去手动查找。',
                  tips: '没有正在播放的歌曲时按钮自动隐藏；背景 / 图标 / 遮罩浓度'
                      '可在主题与背景图片页自定义。',
                ),
              ]),
              const _Section(title: '搜索', icon: Icons.search, children: [
                _Item(
                  title: '歌曲搜索',
                  desc: 'AppBar 搜索图标进入，输入关键词实时过滤（歌名匹配），'
                      '点击结果直接播放（搜索播放 +15 权重）。',
                ),
                _Item(
                  title: 'JSON 查找',
                  desc: '"设置 → JSON 数据内容"页的搜索按钮可在 JSON 原文中查找'
                      '（关键词 / 上下切换 / 两级高亮 / 自动滚动到选中项）。',
                ),
              ]),
              const _Section(title: '播放队列', icon: Icons.queue_music, children: [
                _Item(
                  title: '查看与操作',
                  desc: '底部播放栏的队列图标进入；显示播放顺序、当前歌定位、'
                      '排序编号与"下一首"标记。',
                ),
              ]),
              const _Section(title: '选择音乐文件夹', icon: Icons.folder_open, children: [
                _Item(
                  title: '导入方式',
                  desc: '抽屉"选择音乐文件夹"；选择后扫描该文件夹（不递归子文件夹），'
                      '直接使用原文件路径播放，不复制文件。',
                  tips: '文件夹内新增 / 移除歌曲后，主页下拉刷新即可同步。',
                ),
              ]),
              const _Section(title: '设置 → 主题颜色', icon: Icons.palette_outlined, children: [
                _Item(
                  title: '明暗模式',
                  desc: '日间 / 夜间 / 跟随系统三种，影响全局配色。',
                ),
                _Item(
                  title: '系统推荐主题色',
                  desc: '默认（经典紫）+ 色系两级选择（红 / 橙 / 黄 / 绿 / 蓝 / 紫'
                      '/ 粉 / 青 / 棕 / 灰等，每种色系含 5~10 种常见颜色）。',
                ),
                _Item(
                  title: '自定义颜色',
                  desc: '文字、图标、强调色、状态色、栏与弹窗等均可单独自定义，'
                      '内置调色盘；可一键恢复默认。',
                ),
              ]),
              const _Section(title: '设置 → 背景图片与遮罩浓度', icon: Icons.image_outlined, children: [
                _Item(
                  title: '背景图片',
                  desc: '选择本地图片作为页面背景，可裁剪；支持历史背景图与"移除当前背景"。',
                ),
                _Item(
                  title: '遮罩浓度',
                  desc: '背景 / 抽屉 / 悬浮定位按钮的遮罩浓度（日 / 夜分开），'
                      '值越大越不透明，保证文字清晰。',
                ),
              ]),
              const _Section(title: '设置 → 默认停留页', icon: Icons.home_outlined, children: [
                _Item(
                  title: '停留页恢复',
                  desc: '开关打开（默认）：每次打开 app 回到上次退出时停留的页面；'
                      '关闭则每次进入主页。',
                ),
              ]),
              const _Section(title: '设置 → JSON 数据内容', icon: Icons.data_object, children: [
                _Item(
                  title: '调试用途',
                  desc: '查看歌曲库 / 播放队列 / 歌单库的原始 JSON，支持查找、复制；'
                      '一般用户无需操作。',
                ),
              ]),
              const _Section(title: '常用操作与注意事项', icon: Icons.info_outline, children: [
                _Item(
                  title: '长按歌曲菜单',
                  desc: '长按任意歌曲弹出菜单：加入歌单、添加下一首、收藏 / 取消收藏、'
                      '设置权重、歌曲信息。',
                ),
                _Item(
                  title: '抽屉打开方式',
                  desc: '点击左上角按钮，或在页面大部分区域从屏幕左侧向右滑动。',
                ),
                _Item(
                  title: '通知栏与锁屏',
                  desc: '后台播放时通知栏与锁屏提供播放 / 暂停、上一首 / 下一首，'
                      '与 app 内队列完全同步。',
                ),
                _Item(
                  title: '退出恢复',
                  desc: '播放中退出 app：下次打开恢复显示但保持暂停，需手动点击播放。',
                ),
                _Item(
                  title: '数据安全',
                  desc: '所有音乐数据仅保存在本机，不上传任何内容；关闭 app 不丢失收藏、'
                      '权重与歌单。',
                ),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}

/// 功能分组：标题 + 图标 + 子条目
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.icon, required this.children});

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Row(
            children: [
              Icon(icon, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        ...children,
      ],
    );
  }
}

/// 单个功能介绍条目：标题 + 简介 + 注意事项
class _Item extends StatelessWidget {
  const _Item({required this.title, required this.desc, this.tips});

  final String title;
  final String desc;
  final String? tips;

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(desc, style: TextStyle(color: secondary, height: 1.5)),
          if (tips != null) ...[
            const SizedBox(height: 2),
            Text(
              '提示：$tips',
              style: TextStyle(
                color: secondary,
                height: 1.5,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
