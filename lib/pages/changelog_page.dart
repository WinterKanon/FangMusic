import 'package:flutter/material.dart';

import '../models/theme_palette.dart';
import '../widgets/app_background.dart';

/// "更新日志"页（v1.0 实装；v1.1 补版本）
///
/// 从"设置 → 关于"进入。汇总从 v0.0 到 v1.1 的全部更新记录，最新在最前。
/// 布局与其余页面一致：页面级背景 + 透明 AppBar + ListView。
class ChangelogPage extends StatelessWidget {
  const ChangelogPage({super.key});

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return Stack(
      children: [
        //页面级背景（背景 + 遮罩在 Scaffold 之下，页面出现即带背景）
        const AppBackground(pageKey: ThemePalette.pageKeySettingsPages),
        Scaffold(
          appBar: AppBar(title: const Text('更新日志'), centerTitle: true),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Text(
                  'FangMusic 从 v0.0 到 v1.2 的更新记录',
                  style: TextStyle(color: secondary, fontSize: 12),
                ),
              ),
              const _LogEntry(
                version: 'v1.2.1',
                date: '2026-11-01',
                items: [
                  '修复：未设置背景图时播放详情页/歌曲信息弹窗黑底',
                  '修复：睡眠定时“播完当前歌曲”后未暂停、继续下一首',
                  '新增：播放详情页倍速播放（0.25x-5x + 自定义），'
                      '切换歌曲/换源后保持',
                  '新增：设置各页面背景图片支持“播放详情页”独立背景',
                  '修复：移除全局背景后，已自定义背景的页面仍正常显示',
                ],
              ),
              const _LogEntry(
                version: 'v1.2',
                date: '2026-10-31',
                items: [
                  '列表信息栏与排序：添加时间 / 歌名（拼音 A-Z/Z-A）/ 时长 / 播放次数，'
                      '主页排序同步顺序播放队列',
                  '收藏 / 歌单独立排序与默认顺序；收藏来源队列按收藏顺序生成',
                  '播放次数统计：连续播放 ≥5 秒计 1 次，歌曲详情显示，删除清理',
                  '多选批量：仅移除库 / 永久删除 / 加入歌单 / 添加下一首；'
                      '多选长按拖动自定义顺序',
                  '播放界面页：封面占位、进度控制、歌词占位；'
                      '底部导航（模式 / 倍速 / 睡眠 / 更多 / 队列）',
                  '倍速播放：0.25x - 5x 预设与自定义倍速',
                  '睡眠定时：立即暂停或播完当前歌曲暂停；移除底部播放栏模式图标，'
                      '播放模式入口移至信息栏',
                ],
              ),
              const _LogEntry(
                version: 'v1.1',
                date: '2026-10-30',
                items: [
                  '数据安全：收藏 / 权重独立持久化，全库原子写 + .bak 备份 + 启动自愈'
                      '（修复偶发"打开 app 歌曲全消失"）',
                  '删除歌曲（含本地文件；Android 11+ 引导"所有文件访问"授权）；'
                      '"标记不喜欢"与基准权重模型；播放队列"减号"移除与权重联动',
                  '按页背景图片与遮罩：主页 / 收藏 / 自定义歌单 / 播放队列（按播放源）/ '
                      '搜索 / 设置 / JSON / 关于，含页面预览与历史背景图；'
                      '新增"清除各页面的自定义设置"',
                  '设置新增"所选文件夹管理"：查看 / 移除已选择的音乐文件夹'
                      '（仅移出 app，不删除文件）；修复相册 Pictures 中多余副本',
                  'JSON 数据内容页懒加载、行距优化、关键词编辑查找、两级高亮与黄金分割定位',
                  '主题色默认日白夜黑；队列"下一首"标记图标化并可自定义颜色',
                  '播放模式切换完全无感：双播放器静音预加载 + 瞬时交换'
                      '（audio_service 自建通知栏/锁屏）',
                  '关于页改版：三段简介、数据隐私、致谢与作者署名；版本号更新为 v1.1',
                ],
              ),
              const _LogEntry(
                version: 'v1.0 第四阶段',
                date: '2026-10-27',
                items: [
                  'JSON 数据内容入口移至设置页；JSON 查找补全（关键词 / 上下切换 / '
                      '两级高亮 / 选中自动滚动）',
                  '通知栏与锁屏上一首 / 下一首（整池队列加载，与 app 内队列完全一致，'
                      '含"添加下一首"插入任务与重复歌曲多轮次对齐）',
                  '主页 / 收藏 / 歌单页"定位当前播放歌曲"悬浮按钮'
                      '（背景、文字、遮罩浓度均可自定义）',
                  '退出恢复：回到上次停留页面；播放中退出后恢复显示但保持暂停',
                  '批量加入歌单；主页下拉刷新；播放模式切换不打断当前歌曲',
                  '关于页实装；主题 / 背景图片页重命名；恢复默认设置（仅主题颜色页）',
                ],
              ),
              const _LogEntry(
                version: 'v1.0 第三阶段',
                date: '2026-10-26',
                items: [
                  '歌单：新建 / 重命名（长按）/ 删除，抽屉三段式布局',
                  '播放源：全部歌曲 / 我的收藏 / 自定义歌单',
                  '长按歌曲统一菜单（加入歌单、添加下一首、收藏、设置权重、歌曲信息）',
                  '提示浮层置顶 + 主题化；抽屉遮罩浓度可调；播放队列入口补齐',
                ],
              ),
              const _LogEntry(
                version: 'v1.0 第二阶段',
                date: '2026-10-22',
                items: [
                  '权重体系：手动设置 / 事件调权（收藏、添加下一首、搜索播放、'
                      '单曲循环、快切、完整播完）/ 7 天回归 / 加权随机播放',
                  '设置 → 权重调节页（调权数值、权重范围、保存）',
                ],
              ),
              const _LogEntry(
                version: 'v1.0 第一阶段',
                date: '2026-10-18',
                items: [
                  '主题：日间 / 夜间 / 跟随系统；系统推荐主题色（默认 + 色系两级选择）',
                  '自定义颜色（文字、图标、强调色、状态色、栏与弹窗等，含调色盘）；'
                      '背景图片（选图、裁剪、遮罩浓度、历史背景图）',
                  '搜索、收藏、排序、播放队列、JSON 调试页',
                ],
              ),
              const _LogEntry(
                version: 'v0.0',
                date: '2026-10-17',
                items: [
                  '首个正式版本（重写阶段 1~6 全部完成）：',
                  '文件夹扫描导入（不递归子文件夹，直接使用原文件路径，不复制）',
                  '歌曲列表（歌名 + 时长、连续序号、排序）；点击播放 / 暂停、上一首 / 下一首',
                  '底部播放栏（歌名滚动、进度条、播放 / 暂停）；后台播放'
                      '（通知栏控制、锁屏播放）',
                  '播放模式：顺序（首尾循环）/ 单曲循环 / 普通随机（50 首批次 + 滑动窗口）',
                  '播放队列页（当前歌定位、排序编号、下一首标记）；"添加下一首"',
                  '加权随机播放（按概率 CDF 采样）；权重系统（6 种行为调权、播放衰减、'
                      '7 天回归、概率重算）',
                  '搜索页（实时过滤、搜索播放调权）；收藏（+200 调权）；排序',
                  '主题色切换（6 色预设）；JSON 数据查看页',
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }
}

/// 更新日志条目：版本 + 日期 + 功能列表
class _LogEntry extends StatelessWidget {
  const _LogEntry({required this.version, required this.date, required this.items});

  final String version;
  final String date;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                version,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Text(date, style: TextStyle(color: secondary, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Text('· $item', style: TextStyle(color: secondary, height: 1.5)),
            ),
        ],
      ),
    );
  }
}
