import 'package:flutter/foundation.dart';

import '../models/song.dart';
import '../models/song_weight_data.dart';
import '../models/weight_behavior.dart';
import 'storage_service.dart';
import 'weight_config_service.dart';

/// 权重调整服务（阶段4：加权随机 + 权重系统核心；v1.1 权重独立化 + 基准模型）
///
/// 职责：
/// - 持有**权威**的权重数据（`weights.json`，按音频路径关联，与歌曲库解耦——
///   歌曲库损坏/被清空时权重不丢失；删除歌曲时按路径清理）
/// - 8 种行为调权（增量来自 [WeightConfigService]，数值可配置；<br/>
///   权重范围同样由 [WeightConfigService] 配置，默认 [20,500]，<br/>
///   所有调权/手动设定/回归统一按配置范围 clamp）
/// - **基准权重（v1.1）**：每首歌有 baseWeight（默认 100，可自定义）；
///   播放衰减只衰减超出基准的部分；7 天回归的目标 = 基准（而非固定 100）
/// - **标记不喜欢（v1.1）**：baseWeight 降为配置值（默认 60）+ 当前权重减
///   配置值（默认 20）；"播放队列移除"（v1.1）按配置减权 / 撤销添加加分
/// - 播放衰减：加权随机模式下周期内第 1~4 次播放各减超出基准部分的 20%
/// - 7 天回归：>基准且 7 天无增加/回归 → 向基准回 5%；
///   <基准且 7 天无减少/回归 → 向基准回 2%
///
/// 写库只经 [StorageService]；权重变化后自动持久化（weights.json）并广播。
/// 全局唯一实例。
class WeightService extends ChangeNotifier {
  static final WeightService instance = WeightService._();
  WeightService._();

  /// 权威权重数据（路径 → 权重数据）。
  /// v1.1 起不再以 Song 对象为权威（此前权重存 songs.json 的 Song.weight，
  /// 歌曲库损坏会连权重一起丢失——已独立化修复）。
  Map<String, SongWeightData> _weights = {};

  /// 加权随机周期内各歌的播放次数（内存计数，不落库；
  /// 切到加权随机模式时由 [resetDecayCounts] 清零）
  final Map<String, int> _decayPlayCount = {};

  //==================== 加载 ====================

  /// 从本地加载权威权重库（App 启动 / 库加载时调用）。
  ///
  /// **幂等**：磁盘有数据则整体替换（首次启动）；若本服务已有权威数据
  /// （重复调用/热重载场景）则合并——已有的路径保留内存值（最新），
  /// 磁盘上新增的路径补进来。
  Future<void> load() async {
    final disk = await StorageService.loadWeights();
    if (disk.isEmpty) return; //磁盘无数据：保持现状（首次启动为空）
    if (_weights.isEmpty) {
      _weights = disk;
    } else {
      for (final e in disk.entries) {
        _weights.putIfAbsent(e.key, () => e.value);
      }
    }
  }

  //==================== 库同步 ====================

  /// 歌曲库同步（`LibraryProvider.loadSongs` / 排序 / 收藏后调用）。
  ///
  /// v1.1 语义：**权重权威在 _weights**，与传入 Song 对象无关——
  /// - 清理：库中已不存在的路径（歌曲被删除/移出）→ 移除权重记录
  /// - 迁移：新路径（_weights 中还没有）从 Song 的 weight/baseWeight/时间戳
  ///   初始化（兼容旧数据与测试构造的 Song 传入值）
  /// - 保留：已有路径的权重**不被传入列表覆盖**（修复 v1.0 第二阶段
  ///   "权重乱跳"根因；v1.1 起权威独立，天然免疫）
  void updateLibrary(List<Song> songs) {
    final newPaths = songs.map((s) => s.audioFilePath).toSet();
    //1. 清理已不在库中的路径
    _weights.removeWhere((path, _) => !newPaths.contains(path));
    //2. 迁移/保留
    for (final s in songs) {
      if (!_weights.containsKey(s.audioFilePath)) {
        _weights[s.audioFilePath] = SongWeightData(
          weight: s.weight,
          baseWeight: s.baseWeight,
          lastWeightIncreaseTime: s.lastWeightIncreaseTime,
          lastWeightDecreaseTime: s.lastWeightDecreaseTime,
        );
      }
    }
    notifyListeners();
  }

  /// 按路径查询当前权重（播放队列加权采样用）；
  /// 找不到返回 null，调用方回退默认 100
  double? weightOf(String audioFilePath) {
    return _weights[audioFilePath]?.weight;
  }

  /// 按路径查询基准权重；找不到返回 null，调用方回退默认 100
  double? baseWeightOf(String audioFilePath) {
    return _weights[audioFilePath]?.baseWeight;
  }

  //==================== 行为调权 ====================

  /// 按行为对某歌调权（核心入口）：
  /// 增量取 [WeightConfigService.deltaFor] → clamp 到配置范围 →
  /// 更新对应时间戳（增 → lastWeightIncreaseTime，减 → lastWeightDecreaseTime）
  /// → 持久化并广播
  Future<void> applyBehavior(Song song, WeightBehavior behavior) async {
    await _changeWeight(song, WeightConfigService.instance.deltaFor(behavior));
  }

  /// 直接增减某歌权重（所有调权/衰减/回归的公共底座）
  Future<void> _changeWeight(Song song, double delta) async {
    if (delta == 0) return;
    final path = song.audioFilePath;
    //防御：库外歌曲（理论不会出现）按 Song 初始数据兜底建条目
    final cur = _weights[path] ??
        SongWeightData(
          weight: song.weight,
          baseWeight: song.baseWeight,
          lastWeightIncreaseTime: song.lastWeightIncreaseTime,
          lastWeightDecreaseTime: song.lastWeightDecreaseTime,
        );
    //按配置范围 clamp（默认 [20,500]，用户可改）
    final newWeight =
        WeightConfigService.instance.clampWeight(cur.weight + delta);
    if (newWeight == cur.weight) return; // 已在边界，无需变化
    final now = DateTime.now().toIso8601String();
    _weights[path] = cur.copyWith(
      weight: newWeight,
      lastWeightIncreaseTime: delta > 0 ? now : cur.lastWeightIncreaseTime,
      lastWeightDecreaseTime: delta < 0 ? now : cur.lastWeightDecreaseTime,
    );
    await _persist();
  }

  //==================== 标记不喜欢（v1.1）====================

  /// "标记不喜欢"：一次操作同时
  /// - 把该歌**基准权重**降为配置值（默认 60，clampRange 收敛到范围最近边界）
  /// - 把**当前权重**减配置值（默认 -20，clamp 到范围）
  ///
  /// 7 天回归的目标随后 = 新基准（不喜欢后不会回到 100，符合直觉）。
  Future<void> markUnliked(Song song) async {
    final path = song.audioFilePath;
    final cur = _weights[path];
    if (cur == null) return; //库外歌曲：忽略（与其它调权一致防御）
    final config = WeightConfigService.instance;
    final newBase = config.clampRange(config.unlikeBaseWeight);
    final newWeight = config.clampWeight(cur.weight + config.unlikeDelta);
    _weights[path] = cur.copyWith(
      baseWeight: newBase,
      weight: newWeight,
      lastWeightDecreaseTime: DateTime.now().toIso8601String(),
    );
    await _persist();
  }

  //==================== 播放队列移除（v1.1）====================

  /// 从播放队列移除歌曲时的权重联动：
  /// - 普通移除：`weight -= queueRemoveDelta`（默认 5，可配置）
  /// - 移除"添加下一首"标记歌：**撤销添加时的加分**
  ///   （`weight -= addNext` 配置值；添加时 +addNext → 移除时 -addNext）
  Future<void> removeFromQueue(Song song, {bool wasNextSong = false}) async {
    final config = WeightConfigService.instance;
    final delta = wasNextSong ? -config.addNext : config.queueRemoveDelta;
    await _changeWeight(song, delta);
  }

  //==================== 播放衰减 ====================

  /// 播放衰减：加权随机模式下每次播放某歌时调用。
  ///
  /// 周期内第 1~4 次播放各减"超出**基准（baseWeight）**部分"的 20%，
  /// 第 5 次起不再衰减；切到加权随机模式时 [resetDecayCounts] 清零计数。
  Future<void> applyPlayDecay(Song song) async {
    final count = (_decayPlayCount[song.audioFilePath] ?? 0) + 1;
    _decayPlayCount[song.audioFilePath] = count;
    if (count > 4) return; // 第 5 次起不再衰减
    final data = _weights[song.audioFilePath];
    if (data == null) return;
    if (data.weight <= data.baseWeight) return; // 只有超出基准的部分才衰减
    final delta = -(data.weight - data.baseWeight) * 0.2;
    await _changeWeight(song, delta);
  }

  /// 清空周期播放计数（切到加权随机模式时调用）
  void resetDecayCounts() {
    _decayPlayCount.clear();
  }

  //==================== 7 天回归 ====================

  /// 7 天回归：App 启动 / 切到加权随机时扫描全库。
  ///
  /// 目标 = 该歌的**基准权重 baseWeight**（v1.1；此前固定 100）：
  /// - weight > base 且 7 天无**增加**（且 7 天无回归记录）→ 向 base 回归 5%
  /// - weight < base 且 7 天无**减少**（且 7 天无回归记录）→ 向 base 回归 2%
  ///
  /// 目标经 clampRange 收敛到配置范围（如基准 60 不在 [200,500] 内 → 200）。
  /// 回归后更新**对应方向**的时间戳，保证 7 天观察期内不重复回归。
  Future<void> applySevenDayRegression() async {
    if (_weights.isEmpty) return;
    final now = DateTime.now();
    final updated = <String, SongWeightData>{};
    for (final e in _weights.entries) {
      final s = e.value;
      final target = WeightConfigService.instance.clampRange(s.baseWeight);
      final daysSinceIncrease = _daysSince(s.lastWeightIncreaseTime, now);
      final daysSinceDecrease = _daysSince(s.lastWeightDecreaseTime, now);
      var changed = s;
      var modified = false;
      if (s.weight > target &&
          (daysSinceIncrease == null || daysSinceIncrease >= 7) &&
          (daysSinceDecrease == null || daysSinceDecrease >= 7)) {
        // 向目标收敛 5% 差距：new = weight + (target - weight) * 0.05
        changed = s.copyWith(
          weight: WeightConfigService.instance
              .clampWeight(s.weight + (target - s.weight) * 0.05),
          lastWeightDecreaseTime: now.toIso8601String(),
        );
        modified = true;
      } else if (s.weight < target &&
          (daysSinceDecrease == null || daysSinceDecrease >= 7) &&
          (daysSinceIncrease == null || daysSinceIncrease >= 7)) {
        // 向目标收敛 2% 差距：new = weight + (target - weight) * 0.02
        changed = s.copyWith(
          weight: WeightConfigService.instance
              .clampWeight(s.weight + (target - s.weight) * 0.02),
          lastWeightIncreaseTime: now.toIso8601String(),
        );
        modified = true;
      }
      if (modified) updated[e.key] = changed;
    }
    if (updated.isEmpty) return;
    _weights.addAll(updated);
    await _persist();
  }

  /// 距今天数；时间戳为空或解析失败返回 null（表示无记录）
  int? _daysSince(String iso, DateTime now) {
    if (iso.isEmpty) return null;
    final t = DateTime.tryParse(iso);
    if (t == null) return null;
    return now.difference(t).inDays;
  }

  //==================== 删除歌曲联动（v1.1-2 需求 4）====================

  /// 删除歌曲时同步清理：清除该歌的权重记录（含基准权重）与周期衰减计数。
  /// 记录不存在时静默返回（删除未调过权的歌是正常场景）。
  Future<void> removeSong(String audioFilePath) async {
    final removed = _weights.remove(audioFilePath);
    _decayPlayCount.remove(audioFilePath);
    if (removed != null) await _persist();
  }

  //==================== 持久化 ====================

  /// 持久化权威权重（weights.json，原子写 + .bak 自愈）并广播。
  /// 写库失败不致命（下次变化会再写）；测试环境无平台通道时静默。
  Future<void> _persist() async {
    try {
      await StorageService.saveWeights(_weights);
    } catch (e) {
      debugPrint('[weight] 写权重库失败：$e');
    }
    notifyListeners();
  }

  //==================== 手动设定 / 重置 ====================

  /// 手动设定某首歌的权重（v1.0 第二阶段：歌曲长按菜单"设置权重"入口）。
  ///
  /// - 范围按配置 clamp（默认 [20,500]，用户可改）
  /// - 设定后随默认听歌行为正常增减
  /// - lastWeightIncreaseTime 更新为设定时刻（避免 7 天回归误触发）
  Future<void> setManualWeight(Song song, double weight) async {
    final path = song.audioFilePath;
    final cur = _weights[path];
    if (cur == null) return;
    final v = WeightConfigService.instance.clampWeight(weight);
    _weights[path] = cur.copyWith(
      weight: v,
      lastWeightIncreaseTime: DateTime.now().toIso8601String(),
    );
    await _persist();
  }

  /// 重置单曲权重为 100（100 不在配置范围时重置到最近边界，见 clampRange）；
  /// **基准权重一并恢复为 100**（"重置 100" = 完全恢复默认，标记不喜欢后
  /// 点此可彻底还原）
  Future<void> resetSongWeight(Song song) async {
    final path = song.audioFilePath;
    final cur = _weights[path];
    if (cur == null) return;
    final v = WeightConfigService.instance.clampRange(100);
    _weights[path] = cur.copyWith(
      weight: v,
      baseWeight: v,
      lastWeightIncreaseTime: DateTime.now().toIso8601String(),
    );
    await _persist();
  }

  /// 重置全部歌曲权重为 100（100 不在配置范围时重置到最近边界）；
  /// 基准权重一并恢复默认
  Future<void> resetAllWeights() async {
    if (_weights.isEmpty) return;
    final v = WeightConfigService.instance.clampRange(100);
    final now = DateTime.now().toIso8601String();
    final map = <String, SongWeightData>{};
    for (final e in _weights.entries) {
      map[e.key] = e.value.copyWith(
        weight: v,
        baseWeight: v,
        lastWeightIncreaseTime: now,
      );
    }
    _weights = map;
    await _persist();
  }

  /// 收藏行为调权（阶段5 接入）。
  /// 收藏 → +配置值；取消收藏 → -配置值（v1.0 第二阶段新增事件）
  Future<void> onFavorite(Song song, bool isFavorite) async {
    await applyBehavior(
      song,
      isFavorite ? WeightBehavior.favorite : WeightBehavior.unfavorite,
    );
  }

  /// 搜索播放调权（预留：搜索 UI 在阶段5 接入）
  Future<void> onSearchPlay(Song song) async {
    await applyBehavior(song, WeightBehavior.searchPlay);
  }

  //==================== 测试辅助 ====================

  /// 仅供测试：重置内部状态（不碰磁盘）
  @visibleForTesting
  void resetForTest() {
    _weights = {};
    _decayPlayCount.clear();
  }
}
