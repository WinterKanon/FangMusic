import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:fs_music_app/providers/playlist_provider.dart';
import 'package:fs_music_app/widgets/left_drawer_widget.dart';

void main() {
  testWidgets('抽屉布局：分割线与"我的收藏"紧贴（间距 < 20px）', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => PlaylistProvider(),
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(),
            drawer: LeftDrawerWidget(
              onScanFolder: () {},
              onFavoritesTap: () {},
            ),
            body: const SizedBox(),
          ),
        ),
      ),
    );

    //打开抽屉
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();

    //分割线（抽屉里只有中部/歌单区这一根）
    final dividerRect = tester.getRect(find.byType(Divider));
    final aboutRect = tester.getRect(find.text('关于'));
    final favoritesRect = tester.getRect(find.text('我的收藏'));

    //"我的收藏"与分割线的间距 = "关于"与其下方分割线的间距（对称、字体一致）
    final gapBelow = favoritesRect.top - dividerRect.bottom; //分割线→我的收藏
    final gapAbove = dividerRect.top - aboutRect.bottom; //关于→分割线
    expect((gapBelow - gapAbove).abs(), lessThan(5.0));

    //结构健全：中部功能集 + 歌单区都在
    expect(find.text('选择音乐文件夹'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);
    expect(find.text('新建歌单'), findsOneWidget);
  });
}
