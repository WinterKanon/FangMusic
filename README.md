# FangMusic

一款专注本地音乐播放的 Flutter Android 应用：无广告、无需联网，导入本地音乐即可使用。

- 版本：v1.2.1（`1.2.1+4`）
- 平台：Android
- 作者：方始
- 反馈：3930446985@qq.com

## 下载

- **最新版本**：[GitHub Releases / Latest](https://github.com/WinterKanon/FangMusic/releases/latest)
- **全部版本**：[GitHub Releases](https://github.com/WinterKanon/FangMusic/releases)

进入 Releases 页面后，在对应版本的 **Assets** 中下载 `.apk` 文件安装。
APK 不放在源码仓库里，避免仓库体积过大；每个版本会附带更新说明与安装包。

> 如果 Releases 页面暂时为空，说明对应版本安装包还未上传。

## 功能

- 本地音乐扫描与歌曲库管理（所选文件夹、下拉刷新、文件夹移除）
- 收藏、自定义歌单、搜索、播放队列
- 顺序播放 / 单曲循环 / 普通随机 / 加权随机；双播放器无感切换
- 通知栏 / 锁屏控制（audio_service）
- 播放次数统计、列表信息栏与排序（添加时间 / 歌名拼音 / 时长 / 次数 / 自定义）
- 多选批量：仅移除库、永久删除、加入歌单、添加下一首；长按拖动排序
- 播放界面页；睡眠定时（立即暂停 / 播完当前歌曲暂停，自定义 1–120 分钟）
- 主题与逐页背景自定义、JSON 数据查看、权重调节等

## 开发与构建

环境：Flutter 3.50+ / Dart 3.11+。

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

调试包：

```bash
flutter build apk --debug
```

发布包请自行配置签名后执行 `flutter build apk --release`。

## 目录

```text
lib/
  models/      数据模型
  pages/       页面
  providers/   Provider 状态
  services/    播放、队列、排序、统计、存储、睡眠定时等
  widgets/     复用组件
docs/          v1.2 规划与完成记录
test/          单元与组件测试
```

关键设计：

- 播放队列 `PlaylistService` 为单一权威队列，播放器池为快照；
- 双播放器（active/standby）静音预加载 + 瞬时交换，切模式/排序不断音；
- 列表排序偏好持久化在 `list_view_database.json`，播放次数在 `play_stats_database.json`；
- 所有数据仅保存在本机。

## 数据与隐私

歌曲信息、收藏、歌单、权重、播放次数与设置均保存在应用私有目录，不上传服务器，不收集使用数据。

## 许可证

本项目采用 **PolyForm Noncommercial License 1.0.0**：
允许个人学习、研究、修改与再分发，**不允许收费或商业使用**。完整条款见 [LICENSE](LICENSE)。
如需商业授权，请联系作者：3930446985@qq.com。

> 本项目采用“非商业免费 + 商业授权”的双许可模式；**暂不接受外部贡献/PR**（欢迎反馈 issue）。
> 公开仓库中的 fork 仍受非商业许可约束，不能用于收费。

> 说明：PolyForm Noncommercial 属于“源码可用（source-available）”许可，并非 OSI 定义的开源许可（OSI 不允许限制使用领域）。

## 第三方组件

主要依赖及其许可证（完整列表见应用内「关于 → 开源许可」）：

- Flutter / Dart — BSD-3-Clause
- just_audio、audio_service、audio_session — MIT
- provider、shared_preferences、path_provider — BSD-3-Clause / MIT
- permission_handler、file_picker、image_cropper、marquee — MIT / BSD
- pinyin 3.3.0 — BSD-2-Clause

## 免责声明

本项目仅提供本地音频播放能力，不附带任何音乐内容。请确保你拥有所播放音频的合法使用权；因使用本项目产生的版权或其他法律责任由使用者自行承担。
