import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fs_music_app/app.dart';
import 'package:fs_music_app/pages/about_page.dart';
import 'package:fs_music_app/pages/settings_page.dart';

void main() {
  testWidgets('冒烟测试：主页可正常构建并显示初始加载态', (tester) async {
    await tester.pumpWidget(const MusicApp());

    //App 骨架构建成功
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.text('Music'), findsOneWidget);

    //初始加载中：出现加载指示器
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    //注意：测试环境无真实平台通道（path_provider），真实数据加载由真机验证，
    //此处不做 pumpAndSettle，避免平台通道挂起导致超时。
  });

  testWidgets('冒烟测试：关于页可正常构建（v1.1 改版）', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutPage()));

    //app 介绍 + 数据隐私/致谢（v1.1 新增）
    expect(find.text('FangMusic'), findsOneWidget);
    expect(find.text('v1.2.1 · 本地音乐播放器'), findsOneWidget);
    expect(find.textContaining('方始'), findsOneWidget);
    expect(find.text('数据隐私'), findsOneWidget);
    expect(find.text('致谢'), findsOneWidget);
    //更新日志/使用介绍入口在下方：滚动后可见（ListView 懒加载）
    await tester.scrollUntilVisible(
      find.text('更新日志'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('更新日志'), findsOneWidget);
    expect(find.text('使用介绍'), findsOneWidget);
    //支持与反馈在列表底部
    await tester.scrollUntilVisible(
      find.text('意见反馈'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('意见反馈'), findsOneWidget);
    expect(find.textContaining('3930446985@qq.com'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('开源许可'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('开源许可'), findsOneWidget);
  });

  testWidgets('冒烟测试：设置页含调试分区与 JSON 入口（v1.0 第四阶段）',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));

    //原分区保留：外观 / 播放（视口内可见）
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('播放'), findsOneWidget);
    //调试分区在列表底部：滚动后可见（第四阶段从抽屉移入设置页）
    await tester.scrollUntilVisible(
      find.text('JSON 数据内容'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('调试'), findsOneWidget);
    expect(find.text('JSON 数据内容'), findsOneWidget);
  });
}
