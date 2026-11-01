/// 权重调整行为类型（阶段4：加权随机 + 权重系统）
///
/// 每种行为对应一个**可配置**的调权数值（见 [WeightConfigService]），
/// 默认值 = docs/02 定稿 + v1.0 第二阶段新增：
/// - 手动点击 +30
/// - 收藏 +200
/// - 添加下一首 +20
/// - 搜索播放 +15
/// - 单曲循环重播 +8
/// - 10 秒内快切 -25
/// - 完整播完一首 +8（v1.0 第二阶段新增）
/// - 取消收藏 -150（v1.0 第二阶段新增）
enum WeightBehavior {
  manualClick('手动点击'),
  favorite('收藏'),
  addNext('添加下一首'),
  searchPlay('搜索播放'),
  repeatOne('单曲循环重播'),
  quickSkip('10 秒内快切'),
  completedPlaying('完整播完'),
  unfavorite('取消收藏');

  const WeightBehavior(this.label);

  /// 行为的中文标签（设置界面/调试展示用）
  final String label;
}
