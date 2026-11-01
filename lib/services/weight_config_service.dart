import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/weight_behavior.dart';

/// 调权数值与权重范围配置服务（阶段4 + v1.0 第二阶段）
///
/// 8 种听歌行为的调权数值，**默认值 = docs/02 定稿 + 第二阶段新增**：
/// - 手动点击 +30
/// - 收藏 +200
/// - 添加下一首 +20
/// - 搜索播放 +15
/// - 单曲循环重播 +8
/// - 10 秒内快切 -25
/// - 完整播完一首 +8（v1.0 新增）
/// - 取消收藏 -150（v1.0 新增）
///
/// **权重范围**（v1.0 第二阶段新增）：手动权重与所有自动调权的
/// clamp 边界，默认 **[20, 500]**，用户可在设置页配置。
///
/// 存储：SharedPreferences（key 前缀 `weight_config_`）。
/// [setValue] 修改单事件数值、[restoreDefaults] 一键恢复默认、
/// [setWeightRange] 修改权重范围；设置界面在
/// **v1.0 第二阶段**实现（设置 → 权重调节）。
///
/// 全局唯一实例；App 启动时经 `LibraryProvider.loadSongs` 调用 [load]。
class WeightConfigService {
  //==================== 默认值（docs/02 定稿 + v1.0 新增）====================

  static const double manualClickDefault = 30;
  static const double favoriteDefault = 200;
  static const double addNextDefault = 20;
  static const double searchPlayDefault = 15;
  static const double repeatOneDefault = 8;
  static const double quickSkipDefault = -25;
  static const double completedPlayingDefault = 8;
  static const double unfavoriteDefault = -150;

  /// 权重范围默认值（v1.0 第二阶段）
  static const double minWeightDefault = 20;
  static const double maxWeightDefault = 500;

  /// v1.1 新增配置默认值：
  /// - "标记不喜欢"基准：把该歌的**基准权重**降为此值（默认 60）
  /// - "标记不喜欢"减幅：当前权重再减此值（默认 -20）
  /// - "播放队列移除"减幅：队列中移除普通歌曲的惩罚（默认 -5；
  ///   移除"添加下一首"标记歌时按"添加下一首"加分配置值撤销加分）
  static const double unlikeBaseWeightDefault = 60;
  static const double unlikeDeltaDefault = -50;
  static const double queueRemoveDeltaDefault = -5;

  static const String _keyPrefix = 'weight_config_';
  static const String _keyMinWeight = '${_keyPrefix}minWeight';
  static const String _keyMaxWeight = '${_keyPrefix}maxWeight';
  static const String _keyUnlikeBaseWeight = '${_keyPrefix}unlikeBaseWeight';
  static const String _keyUnlikeDelta = '${_keyPrefix}unlikeDelta';
  static const String _keyQueueRemoveDelta = '${_keyPrefix}queueRemoveDelta';

  static final WeightConfigService instance = WeightConfigService._();
  WeightConfigService._();

  //==================== 内部状态 ====================

  double _manualClick = manualClickDefault;
  double _favorite = favoriteDefault;
  double _addNext = addNextDefault;
  double _searchPlay = searchPlayDefault;
  double _repeatOne = repeatOneDefault;
  double _quickSkip = quickSkipDefault;
  double _completedPlaying = completedPlayingDefault;
  double _unfavorite = unfavoriteDefault;
  double _minWeight = minWeightDefault;
  double _maxWeight = maxWeightDefault;
  double _unlikeBaseWeight = unlikeBaseWeightDefault;
  double _unlikeDelta = unlikeDeltaDefault;
  double _queueRemoveDelta = queueRemoveDeltaDefault;
  bool _loaded = false;

  /// 是否已从本地加载（未加载时使用默认值）
  bool get loaded => _loaded;

  //==================== 读取 ====================

  double get manualClick => _manualClick;
  double get favorite => _favorite;
  double get addNext => _addNext;
  double get searchPlay => _searchPlay;
  double get repeatOne => _repeatOne;
  double get quickSkip => _quickSkip;
  double get completedPlaying => _completedPlaying;
  double get unfavorite => _unfavorite;

  /// 权重范围（用户可配置；边界本身也在合理范围内收敛，见 setWeightRange）
  double get minWeight => _minWeight;
  double get maxWeight => _maxWeight;

  /// "标记不喜欢"基准（默认 60）：标记后该歌 baseWeight 降为此值
  double get unlikeBaseWeight => _unlikeBaseWeight;

  /// "标记不喜欢"减幅（默认 -20）：标记后当前权重再减此值
  double get unlikeDelta => _unlikeDelta;

  /// "播放队列移除"减幅（默认 -5）：队列中移除普通歌曲的惩罚
  double get queueRemoveDelta => _queueRemoveDelta;

  /// 取某行为当前的调权数值（增量；可为负，如快切 -25、取消收藏 -150）
  double deltaFor(WeightBehavior behavior) {
    switch (behavior) {
      case WeightBehavior.manualClick:
        return _manualClick;
      case WeightBehavior.favorite:
        return _favorite;
      case WeightBehavior.addNext:
        return _addNext;
      case WeightBehavior.searchPlay:
        return _searchPlay;
      case WeightBehavior.repeatOne:
        return _repeatOne;
      case WeightBehavior.quickSkip:
        return _quickSkip;
      case WeightBehavior.completedPlaying:
        return _completedPlaying;
      case WeightBehavior.unfavorite:
        return _unfavorite;
    }
  }

  //==================== 权重范围工具 ====================

  /// 把权重收敛到当前配置范围内（所有调权/手动设定/回归统一走这里）
  double clampWeight(double value) => value.clamp(_minWeight, _maxWeight);

  /// 把"目标值"映射到范围内：目标不在 [min,max] 时取**最近边界**
  /// （如回归目标 100 在 [200,500] 之外 → 200；在 [20,80] 之外 → 80）
  double clampRange(double target) {
    if (target < _minWeight) return _minWeight;
    if (target > _maxWeight) return _maxWeight;
    return target;
  }

  //==================== 写入 ====================

  /// 从 SharedPreferences 加载配置；
  /// 失败（测试环境无平台通道等）时保持默认值，不崩溃
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _manualClick =
          prefs.getDouble('${_keyPrefix}manualClick') ?? manualClickDefault;
      _favorite = prefs.getDouble('${_keyPrefix}favorite') ?? favoriteDefault;
      _addNext = prefs.getDouble('${_keyPrefix}addNext') ?? addNextDefault;
      _searchPlay =
          prefs.getDouble('${_keyPrefix}searchPlay') ?? searchPlayDefault;
      _repeatOne =
          prefs.getDouble('${_keyPrefix}repeatOne') ?? repeatOneDefault;
      _quickSkip =
          prefs.getDouble('${_keyPrefix}quickSkip') ?? quickSkipDefault;
      _completedPlaying =
          prefs.getDouble('${_keyPrefix}completedPlaying') ??
              completedPlayingDefault;
      _unfavorite =
          prefs.getDouble('${_keyPrefix}unfavorite') ?? unfavoriteDefault;
      _minWeight = prefs.getDouble(_keyMinWeight) ?? minWeightDefault;
      _maxWeight = prefs.getDouble(_keyMaxWeight) ?? maxWeightDefault;
      _unlikeBaseWeight =
          prefs.getDouble(_keyUnlikeBaseWeight) ?? unlikeBaseWeightDefault;
      _unlikeDelta =
          prefs.getDouble(_keyUnlikeDelta) ?? unlikeDeltaDefault;
      _queueRemoveDelta =
          prefs.getDouble(_keyQueueRemoveDelta) ?? queueRemoveDeltaDefault;
      //防止历史脏数据：范围至少为 [1, 2] 且 min ≤ max
      _minWeight = _minWeight.clamp(1.0, _maxWeight);
      _maxWeight = _maxWeight.clamp(_minWeight, 10000.0);
      //基准/减幅收敛到合理范围（基准 1~10000；减幅可负，收敛到 [-10000, 10000]）
      _unlikeBaseWeight = _unlikeBaseWeight.clamp(1.0, 10000.0);
      _unlikeDelta = _unlikeDelta.clamp(-10000.0, 10000.0);
      _queueRemoveDelta = _queueRemoveDelta.clamp(-10000.0, 10000.0);
      _loaded = true;
    } catch (e) {
      debugPrint('[weight-config] 加载配置失败，使用默认值：$e');
    }
  }

  /// 手动设置某个行为的调权数值；立即生效并持久化
  Future<void> setValue(WeightBehavior behavior, double value) async {
    switch (behavior) {
      case WeightBehavior.manualClick:
        _manualClick = value;
        break;
      case WeightBehavior.favorite:
        _favorite = value;
        break;
      case WeightBehavior.addNext:
        _addNext = value;
        break;
      case WeightBehavior.searchPlay:
        _searchPlay = value;
        break;
      case WeightBehavior.repeatOne:
        _repeatOne = value;
        break;
      case WeightBehavior.quickSkip:
        _quickSkip = value;
        break;
      case WeightBehavior.completedPlaying:
        _completedPlaying = value;
        break;
      case WeightBehavior.unfavorite:
        _unfavorite = value;
        break;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('$_keyPrefix${behavior.name}', value);
    } catch (e) {
      debugPrint('[weight-config] 保存配置失败：$e');
    }
  }

  /// 设置权重范围（min/max 均为正整数，min ≤ max）。
  /// 用户填反（min>max）时自动交换纠正；超出 [1,10000] 时收敛到边界，
  /// 不抛异常。
  Future<void> setWeightRange(double min, double max) async {
    //各自先收敛到 [1,10000]，再保证 min ≤ max（填反则交换）
    final a = min.clamp(1.0, 10000.0);
    final b = max.clamp(1.0, 10000.0);
    final lo = a <= b ? a : b;
    final hi = a <= b ? b : a;
    _minWeight = lo;
    _maxWeight = hi;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyMinWeight, lo);
      await prefs.setDouble(_keyMaxWeight, hi);
    } catch (e) {
      debugPrint('[weight-config] 保存权重范围失败：$e');
    }
  }

  /// 设置"标记不喜欢"基准（收敛到 [1,10000]，立即生效并持久化）
  Future<void> setUnlikeBaseWeight(double value) async {
    _unlikeBaseWeight = value.clamp(1.0, 10000.0);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyUnlikeBaseWeight, _unlikeBaseWeight);
    } catch (e) {
      debugPrint('[weight-config] 保存不喜欢基准失败：$e');
    }
  }

  /// 设置"标记不喜欢"减幅（收敛到 [-10000,10000]，立即生效并持久化）
  Future<void> setUnlikeDelta(double value) async {
    _unlikeDelta = value.clamp(-10000.0, 10000.0);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyUnlikeDelta, _unlikeDelta);
    } catch (e) {
      debugPrint('[weight-config] 保存不喜欢减幅失败：$e');
    }
  }

  /// 设置"播放队列移除"减幅（收敛到 [-10000,10000]，立即生效并持久化）
  Future<void> setQueueRemoveDelta(double value) async {
    _queueRemoveDelta = value.clamp(-10000.0, 10000.0);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyQueueRemoveDelta, _queueRemoveDelta);
    } catch (e) {
      debugPrint('[weight-config] 保存队列移除减幅失败：$e');
    }
  }

  /// 一键恢复全部默认调权数值与权重范围（docs/02 定稿）
  Future<void> restoreDefaults() async {
    _manualClick = manualClickDefault;
    _favorite = favoriteDefault;
    _addNext = addNextDefault;
    _searchPlay = searchPlayDefault;
    _repeatOne = repeatOneDefault;
    _quickSkip = quickSkipDefault;
    _completedPlaying = completedPlayingDefault;
    _unfavorite = unfavoriteDefault;
    _minWeight = minWeightDefault;
    _maxWeight = maxWeightDefault;
    _unlikeBaseWeight = unlikeBaseWeightDefault;
    _unlikeDelta = unlikeDeltaDefault;
    _queueRemoveDelta = queueRemoveDeltaDefault;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final b in WeightBehavior.values) {
        await prefs.remove('$_keyPrefix${b.name}');
      }
      await prefs.remove(_keyMinWeight);
      await prefs.remove(_keyMaxWeight);
      await prefs.remove(_keyUnlikeBaseWeight);
      await prefs.remove(_keyUnlikeDelta);
      await prefs.remove(_keyQueueRemoveDelta);
    } catch (e) {
      debugPrint('[weight-config] 恢复默认失败：$e');
    }
  }

  /// 仅供测试：重置为默认值（不碰磁盘）
  @visibleForTesting
  void resetForTest() {
    _manualClick = manualClickDefault;
    _favorite = favoriteDefault;
    _addNext = addNextDefault;
    _searchPlay = searchPlayDefault;
    _repeatOne = repeatOneDefault;
    _quickSkip = quickSkipDefault;
    _completedPlaying = completedPlayingDefault;
    _unfavorite = unfavoriteDefault;
    _minWeight = minWeightDefault;
    _maxWeight = maxWeightDefault;
    _unlikeBaseWeight = unlikeBaseWeightDefault;
    _unlikeDelta = unlikeDeltaDefault;
    _queueRemoveDelta = queueRemoveDeltaDefault;
    _loaded = false;
  }
}
