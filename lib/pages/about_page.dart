import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/theme_palette.dart';
import '../widgets/app_background.dart';
import 'changelog_page.dart';
import 'usage_guide_page.dart';

/// "关于"页（v1.0 实装；v1.1 改版）
///
/// 内容：app 介绍（三段）+ 数据隐私 + 致谢 + 更新日志/使用介绍入口 + 联系作者。
/// 入口：抽屉 → 关于。
/// 布局与其余页面一致：页面级背景 + 透明 AppBar + ListView。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return Stack(
      children: [
        //页面级背景（背景 + 遮罩在 Scaffold 之下，页面出现即带背景）
        const AppBackground(pageKey: ThemePalette.pageKeyAbout),
        Scaffold(
          appBar: AppBar(title: const Text('关于'), centerTitle: true),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              //===== app 介绍 =====
              const SizedBox(height: 32),
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    'assets/icons/app_icon.png',
                    width: 72,
                    height: 72,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Center(
                child: Text(
                  'FangMusic',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  'v1.2.1 · 本地音乐播放器',
                  style: TextStyle(color: secondary, fontSize: 13),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Column(
                  children: [
                    Text('作者：方始',
                        style: TextStyle(color: secondary, fontSize: 12)),
                    Text('天圆地方，万物伊始',
                        style: TextStyle(color: secondary, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _Paragraph(
                'FangMusic 是一款专注于本地音乐体验的播放器，'
                '特色是自定义主题和加权随机播放模式。',
                secondary: secondary,
              ),
              _Paragraph(
                '界面、播放与数据存储均围绕本地曲库设计：无广告、无需联网，'
                '导入自己的音乐即可使用。',
                secondary: secondary,
              ),
              _Paragraph(
                '基于 Flutter 框架构建，本项目的产品设计、功能测试与验收由作者完成，'
                'AI 作为辅助参与编码、调试与文档整理。',
                secondary: secondary,
              ),

              const SizedBox(height: 8),
              const Divider(height: 28, indent: 20, endIndent: 20),

              //===== 数据隐私 =====
              _SectionTitle(
                icon: Icons.shield_outlined,
                title: '数据隐私',
                color: secondary,
              ),
              _Paragraph(
                '所有歌曲信息、歌单、收藏、权重与设置仅保存在本机，'
                '不会上传到任何服务器，也不收集任何使用数据。',
                secondary: secondary,
              ),
              _Paragraph(
                '本项目采用 PolyForm Noncommercial 1.0.0 许可：'
                '允许查阅、学习、修改与再分发，但不得用于收费或商业用途；'
                '第三方组件遵循其各自许可证（见下方“开源许可”）。',
                secondary: secondary,
              ),

              const SizedBox(height: 8),
              //===== 致谢 =====
              _SectionTitle(
                icon: Icons.favorite_border,
                title: '致谢',
                color: secondary,
              ),
              _Paragraph(
                '感谢 Flutter 开源社区，以及 AI 在编码、调试与文档整理中的协助。',
                secondary: secondary,
              ),

              const SizedBox(height: 4),
              _Paragraph(
                '声明：FangMusic 是一款纯粹的本地音频播放器，仅供个人学习使用，'
                '请勿用于商业用途。',
                secondary: secondary,
                italic: true,
                fontSize: 13,
              ),

              const Divider(height: 28, indent: 20, endIndent: 20),

              //===== 更新日志 / 使用介绍入口（独立页面） =====
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('更新日志'),
                subtitle: const Text('从 v0.0 到 v1.2 的更新记录'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ChangelogPage()),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('使用介绍'),
                subtitle: const Text('播放模式、权重、歌单、设置等功能介绍'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const UsageGuidePage()),
                ),
              ),

              const Divider(height: 28, indent: 20, endIndent: 20),

              //===== 联系作者（占位） =====
              _SectionTitle(
                icon: Icons.mail_outline,
                title: '支持与反馈',
                color: secondary,
              ),
              ListTile(
                leading: const Icon(Icons.feedback_outlined),
                title: const Text('意见反馈'),
                subtitle: const Text('3930446985@qq.com（点击复制）'),
                onTap: () async {
                  await Clipboard.setData(
                    const ClipboardData(text: '3930446985@qq.com'),
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      const SnackBar(content: Text('邮箱已复制：3930446985@qq.com')),
                    );
                },
              ),
              ListTile(
                leading: const Icon(Icons.code),
                title: const Text('开源许可'),
                subtitle: const Text('项目许可以及 Flutter / 第三方组件许可证'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'FangMusic',
                  applicationVersion: '1.2.1+4',
                  applicationLegalese: 'Copyright 2026 方始\n'
                      'PolyForm Noncommercial 1.0.0',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 关于页正文段落：统一字号、行距、颜色（跟随主题）
class _Paragraph extends StatelessWidget {
  const _Paragraph(
    this.text, {
    required this.secondary,
    this.italic = false,
    this.fontSize = 14,
  });

  final String text;
  final Color secondary;
  final bool italic;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
      child: Text(
        text,
        style: TextStyle(
          color: secondary,
          height: 1.6,
          fontSize: fontSize,
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// 关于页小节标题：图标 + 标题，颜色跟随主题
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.color,
  });

  final IconData icon;
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
