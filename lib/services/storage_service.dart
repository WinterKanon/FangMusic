import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/play_task.dart';
import '../models/music_folder.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../models/song_play_stat.dart';
import '../models/song_weight_data.dart';

/// 唯一的数据存储入口（架构纪律一：所有 JSON 读写只走这一道门）
///
/// 任何类要读写歌曲库 / 播放队列 / 歌单 / 收藏 / 权重数据，都必须调用
/// 本类的方法，禁止在其他文件中直接操作文件。
///
/// **数据安全（v1.1）**：
/// - 全部库文件统一"原子写 + `.bak` 备份 + 启动自愈"——
///   写入先备份主文件再原子替换；读取主文件损坏时自动回退 `.bak`，
///   回退成功后异步重建主文件；绝不因损坏文件返回空数据覆盖旧库。
/// - 收藏（favorites.json）与权重（weights.json）**独立于歌曲库持久化**，
///   歌曲库损坏/被清空时收藏与权重不丢失（按音频路径关联）。
class StorageService {
  //==================== 文件路径 ====================

  /// 歌曲库 JSON 文件路径（应用文档目录下）
  static Future<String> songsFilePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'home_page_list_database.json');
  }

  /// 播放队列 JSON 文件路径（阶段3 引入）
  static Future<String> playTasksFilePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'home_play_task_database.json');
  }

  /// 用户歌单 JSON 文件路径（v1.0 第三阶段引入）
  static Future<String> playlistsFilePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'playlist_database.json');
  }

  /// 收藏集 JSON 文件路径（v1.1 引入：收藏独立于歌曲库持久化）
  static Future<String> favoritesFilePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'favorite_database.json');
  }

  /// 权重库 JSON 文件路径（v1.1 引入：权重独立于歌曲库持久化）
  static Future<String> weightsFilePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'weight_database.json');
  }

  /// 所选音乐文件夹 JSON（v1.1-5：设置→所选文件夹管理）
  static Future<String> musicFoldersFilePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'music_folders_database.json');
  }

  /// 列表展示偏好 JSON（v1.2：排序方式 / 自定义顺序）
  static Future<String> listViewPrefsFilePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'list_view_database.json');
  }

  /// 播放次数统计 JSON（v1.2）
  static Future<String> playStatsFilePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'play_stats_database.json');
  }

  //==================== 通用原子写 / 自愈 ====================

  /// 读取 JSON 文本并校验可解析；文件不存在/损坏/空返回 null
  static Future<String?> _tryReadJson(File file) async {
    try {
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      jsonDecode(raw); //校验：损坏/空内容返回 null → 触发 .bak 回退
      return raw;
    } catch (_) {
      return null;
    }
  }

  /// 原子写：tmp → rename（先写完整临时文件再替换，
  /// 任何一步中断都不会留下半写的主文件）
  static Future<void> _writeJsonAtomic(File file, String json) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(json);
    if (await file.exists()) {
      await file.delete();
    }
    await tmp.rename(file.path);
  }

  /// **写串行化链**（v1.1-2 修复）：
  /// 所有"备份 + 原子替换"写操作排队执行，避免**并发写同一文件**
  /// 时的 tmp/rename/copy 竞态失败（此前加载重排写库与调权写库
  /// 并发时会抛 PathNotFound / Access denied，导致某次保存未落盘）。
  static Future<void> _writeChain = Future.value();

  /// 带备份的写入（排队入口）：先复制当前主文件为 `.bak`，再原子替换
  /// 主文件，替换成功后清理备份——任何一步中断，下次读取都有 `.bak`
  /// 可回退。返回排队的写任务（调用方 await 时按实际写结果完成）。
  static Future<void> _writeWithBak(File file, String json) {
    final prev = _writeChain;
    final next = prev.then((_) => _writeWithBakInner(file, json));
    //失败不断链：一次写失败不阻塞后续写
    _writeChain = next.catchError((_) {});
    return next;
  }

  static Future<void> _writeWithBakInner(File file, String json) async {
    if (await file.exists()) {
      final bak = File('${file.path}.bak');
      if (await bak.exists()) {
        await bak.delete();
      }
      await file.copy(bak.path);
    }
    await _writeJsonAtomic(file, json);
    final bak = File('${file.path}.bak');
    if (await bak.exists()) {
      await bak.delete();
    }
  }

  /// 读取模式：主文件 → `.bak`（回退成功异步重建主文件）→ null
  static Future<String?> _readWithBak(File file) async {
    final main = await _tryReadJson(file);
    if (main != null) return main;
    final bak = await _tryReadJson(File('${file.path}.bak'));
    if (bak != null) {
      //备份有效：异步重建主文件（容错，不阻塞启动）
      unawaited(_rebuildMainQuietly(file, bak));
      return bak;
    }
    return null;
  }

  /// 用备份内容重建主文件（容错：失败静默，不产生未捕获异步异常）
  static Future<void> _rebuildMainQuietly(File file, String content) async {
    try {
      await _writeJsonAtomic(file, content);
    } catch (_) {
      //重建失败不致命：下次读取仍可回退 .bak
    }
  }

  //==================== 歌曲库 ====================

  /// 读取全部歌曲；文件不存在时创建空库文件并返回空列表。
  ///
  /// **自愈（v1.0 第四阶段 + v1.1 加固）**：主文件损坏/为空时**优先回退
  /// `.bak` 备份**（上一次成功写入的内容）——此前损坏直接返回空列表，
  /// 导致用户"退出后歌曲全消失、需重新选文件夹"。备份也损坏才返回空列表。
  static Future<List<Song>> loadSongs() async {
    final file = File(await songsFilePath());
    if (!await file.exists()) {
      await _writeEmptySongsFile(file);
      return [];
    }
    final raw = await _readWithBak(file);
    if (raw == null) return [];
    return _parseSongs(raw);
  }

  static List<Song> _parseSongs(String raw) {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final list = data['songs'] as List? ?? [];
      return list
          .map((e) => Song.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 写入全部歌曲（保持 JSON 格式与旧项目一致，便于以后迁移/查看）。
  ///
  /// 写前先把当前主文件复制为 `.bak`（上一次成功数据），再原子替换主文件，
  /// 替换成功后删除备份——任何一步中断，下次读取都有 `.bak` 可回退。
  static Future<void> saveSongs(List<Song> songs) async {
    try {
      final file = File(await songsFilePath());
      const encoder = JsonEncoder.withIndent('  ');
      final data = {'songs': songs.map((e) => e.toJson()).toList()};
      await _writeWithBak(file, encoder.convert(data));
    } catch (e) {
      //写库失败不致命：下次写入会重试；测试环境无平台通道时走这里
      debugPrint('[storage] 写歌曲库失败：$e');
    }
  }

  //==================== 收藏集（v1.1 独立持久化）====================

  /// 读取收藏歌曲路径列表（按音频路径关联，与歌曲库解耦）；
  /// 文件不存在/损坏/回退失败返回空列表
  static Future<List<String>> loadFavoritePaths() async {
    final file = File(await favoritesFilePath());
    if (!await file.exists()) return [];
    final raw = await _readWithBak(file);
    if (raw == null) return [];
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final list = data['paths'] as List? ?? [];
      return list.map((e) => e as String).toList();
    } catch (_) {
      return [];
    }
  }

  /// 写入收藏歌曲路径列表（原子写 + `.bak` 备份）
  static Future<void> saveFavoritePaths(List<String> paths) async {
    try {
      final file = File(await favoritesFilePath());
      const encoder = JsonEncoder.withIndent('  ');
      await _writeWithBak(file, encoder.convert({'paths': paths}));
    } catch (e) {
      debugPrint('[storage] 写收藏库失败：$e');
    }
  }

  /// 读取收藏集**原始 JSON 文本**（JSON 调试页展示用，不经解析）；
  /// 文件不存在/读取失败返回 null
  static Future<String?> readFavoritesRaw() async {
    try {
      final file = File(await favoritesFilePath());
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  //==================== 所选音乐文件夹（v1.1-5）====================

  /// 规范化文件夹路径：统一分隔符、去掉末尾斜杠（根目录除外）
  static String normalizeFolderPath(String path) {
    var v = path.trim().replaceAll('\\', '/');
    while (v.length > 1 && v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }

  /// 读取所选文件夹（按添加时间升序）；文件不存在/损坏返回空
  static Future<List<MusicFolder>> loadMusicFolders() async {
    final file = File(await musicFoldersFilePath());
    if (!await file.exists()) return [];
    final raw = await _readWithBak(file);
    if (raw == null) return [];
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final list = data['folders'] as List? ?? [];
      return list
          .map((e) => MusicFolder.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 写入所选文件夹（原子写 + `.bak` 备份）
  static Future<void> saveMusicFolders(List<MusicFolder> folders) async {
    try {
      final file = File(await musicFoldersFilePath());
      const encoder = JsonEncoder.withIndent('  ');
      final data = {'folders': folders.map((e) => e.toJson()).toList()};
      await _writeWithBak(file, encoder.convert(data));
    } catch (e) {
      debugPrint('[storage] 写所选文件夹失败：$e');
    }
  }

  /// 记录一个已选择的文件夹（去重；名称取最后一段）
  static Future<void> addMusicFolder(String dirPath) async {
    final normalized = normalizeFolderPath(dirPath);
    if (normalized.isEmpty) return;
    final folders = await loadMusicFolders();
    if (folders.any((f) => f.path == normalized)) return;
    folders.add(MusicFolder(
      path: normalized,
      name: p.basename(normalized),
      addedAt: DateTime.now().toIso8601String(),
    ));
    await saveMusicFolders(folders);
  }

  /// 移除所选文件夹记录（不删除文件夹与文件）
  static Future<void> removeMusicFolder(String dirPath) async {
    final normalized = normalizeFolderPath(dirPath);
    final folders = await loadMusicFolders();
    final kept = folders.where((f) => f.path != normalized).toList();
    if (kept.length == folders.length) return;
    await saveMusicFolders(kept);
  }

  /// 兼容旧数据：歌曲库已有歌曲但还没有文件夹记录（v1.1-5 之前导入的），
  /// 按歌曲所在目录补录文件夹。不会删除任何已有记录。
  static Future<void> ensureFoldersForSongs(List<Song> songs) async {
    if (songs.isEmpty) return;
    final folders = await loadMusicFolders();
    final existing = folders.map((f) => f.path).toSet();
    var changed = false;
    for (final song in songs) {
      final dir = normalizeFolderPath(p.dirname(song.audioFilePath));
      if (dir.isEmpty || dir == '.') continue;
      if (existing.contains(dir)) continue;
      //已记录父文件夹（前缀）时视为已覆盖
      if (existing.any((f) => song.audioFilePath.startsWith('$f/'))) continue;
      folders.add(MusicFolder(
        path: dir,
        name: p.basename(dir),
        addedAt: DateTime.now().toIso8601String(),
      ));
      existing.add(dir);
      changed = true;
    }
    if (changed) await saveMusicFolders(folders);
  }

  //==================== 列表展示偏好（v1.2）====================

  /// 读取列表展示偏好原始 Map（`{"lists": {...}}`）；
  /// 文件不存在/损坏/回退失败返回 null
  static Future<Map<String, dynamic>?> loadListViewPrefs() async {
    final file = File(await listViewPrefsFilePath());
    if (!await file.exists()) return null;
    final raw = await _readWithBak(file);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// 写入列表展示偏好（原子写 + `.bak` 备份）
  static Future<void> saveListViewPrefs(Map<String, dynamic> data) async {
    try {
      final file = File(await listViewPrefsFilePath());
      const encoder = JsonEncoder.withIndent('  ');
      await _writeWithBak(file, encoder.convert(data));
    } catch (e) {
      debugPrint('[storage] 写列表展示偏好失败：$e');
    }
  }

  //==================== 播放次数统计（v1.2）====================

  static Future<Map<String, SongPlayStat>> loadPlayStats() async {
    final file = File(await playStatsFilePath());
    if (!await file.exists()) return {};
    final raw = await _readWithBak(file);
    if (raw == null) return {};
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final map = data['stats'] as Map<String, dynamic>? ?? {};
      return {
        for (final e in map.entries)
          e.key: SongPlayStat.fromJson(e.value as Map<String, dynamic>),
      };
    } catch (_) {
      return {};
    }
  }

  static Future<void> savePlayStats(Map<String, SongPlayStat> stats) async {
    try {
      final file = File(await playStatsFilePath());
      const encoder = JsonEncoder.withIndent('  ');
      final map = {
        for (final e in stats.entries) e.key: e.value.toJson(),
      };
      await _writeWithBak(file, encoder.convert({'stats': map}));
    } catch (e) {
      debugPrint('[storage] 写播放次数失败：$e');
    }
  }

  //==================== 权重库（v1.1 独立持久化）====================

  /// 读取全部歌曲权重（路径 → 权重数据）；文件不存在/损坏/回退失败返回空
  static Future<Map<String, SongWeightData>> loadWeights() async {
    final file = File(await weightsFilePath());
    if (!await file.exists()) return {};
    final raw = await _readWithBak(file);
    if (raw == null) return {};
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final map = data['weights'] as Map<String, dynamic>? ?? {};
      return {
        for (final e in map.entries)
          e.key: SongWeightData.fromJson(e.value as Map<String, dynamic>),
      };
    } catch (_) {
      return {};
    }
  }

  /// 写入全部歌曲权重（原子写 + `.bak` 备份）
  static Future<void> saveWeights(Map<String, SongWeightData> weights) async {
    try {
      final file = File(await weightsFilePath());
      const encoder = JsonEncoder.withIndent('  ');
      final map = {
        for (final e in weights.entries) e.key: e.value.toJson(),
      };
      await _writeWithBak(file, encoder.convert({'weights': map}));
    } catch (e) {
      debugPrint('[storage] 写权重库失败：$e');
    }
  }

  /// 读取权重库**原始 JSON 文本**（JSON 调试页展示用）；失败返回 null
  static Future<String?> readWeightsRaw() async {
    try {
      final file = File(await weightsFilePath());
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  //==================== 背景图片（v1.0 主题定制）====================

  /// 背景图片目录（应用文档目录/background_images/，不存在则创建）
  static Future<Directory> backgroundImagesDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final sub = Directory(p.join(dir.path, 'background_images'));
    if (!await sub.exists()) {
      await sub.create(recursive: true);
    }
    return sub;
  }

  /// 把用户选的图片复制一份到 app 内（历史背景图片），返回新路径；
  /// 失败返回 null
  static Future<String?> copyToBackgroundDir(String sourcePath) async {
    try {
      final dir = await backgroundImagesDir();
      var ext = p.extension(sourcePath).toLowerCase();
      if (ext.isEmpty) ext = '.png';
      final name = 'bg_${DateTime.now().millisecondsSinceEpoch}$ext';
      final dest = p.join(dir.path, name);
      await File(sourcePath).copy(dest);
      return dest;
    } catch (e) {
      debugPrint('[storage] 复制背景图失败：$e');
      return null;
    }
  }

  /// 列出全部历史背景图片的绝对路径（按名称倒序，新的在前）
  static Future<List<String>> listBackgroundImages() async {
    try {
      final dir = await backgroundImagesDir();
      final files = dir
          .listSync()
          .whereType<File>()
          .map((f) => f.path)
          .toList()
        ..sort((a, b) => b.compareTo(a));
      return files;
    } catch (_) {
      return [];
    }
  }

  /// 删除一张背景图片文件；失败静默（不致命）
  static Future<void> deleteBackgroundImage(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {
      //删除失败不致命
    }
  }

  //==================== 原始 JSON 读取（阶段6 JSON 调试页）====================

  /// 读取歌曲库**原始 JSON 文本**（调试页展示用，不经解析，保持原样）；
  /// 文件不存在/读取失败返回 null
  static Future<String?> readSongsRaw() async {
    try {
      final file = File(await songsFilePath());
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  /// 读取播放队列**原始 JSON 文本**（调试页展示用，不经解析，保持原样）；
  /// 文件不存在/读取失败返回 null
  static Future<String?> readPlayTasksRaw() async {
    try {
      final file = File(await playTasksFilePath());
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeEmptySongsFile(File file) async {
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert({'songs': <dynamic>[]}));
  }

  //==================== 播放队列（阶段3，v1.1 加 .bak 回退）====================

  /// 读取播放队列；文件不存在/损坏（含 .bak 也损坏）返回空列表
  /// （由调用方决定按模式生成）
  static Future<List<PlayTask>> loadPlayTasks() async {
    final file = File(await playTasksFilePath());
    if (!await file.exists()) return [];
    final raw = await _readWithBak(file);
    if (raw == null) return [];
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final list = data['tasks'] as List? ?? [];
      return list
          .map((e) => PlayTask.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 写入播放队列（原子写 + `.bak` 备份）
  static Future<void> savePlayTasks(List<PlayTask> tasks) async {
    try {
      final file = File(await playTasksFilePath());
      const encoder = JsonEncoder.withIndent('  ');
      final data = {'tasks': tasks.map((e) => e.toJson()).toList()};
      await _writeWithBak(file, encoder.convert(data));
    } catch (e) {
      //写队列失败不致命（队列可在下次启动重建）
      debugPrint('[storage] 写播放队列失败：$e');
    }
  }

  //==================== 用户歌单（v1.0 第三阶段，v1.1 加 .bak 回退）====================

  /// 读取用户歌单；文件不存在/损坏（含 .bak 也损坏）返回空列表
  /// （由调用方决定处理）
  static Future<List<Playlist>> loadPlaylists() async {
    final file = File(await playlistsFilePath());
    if (!await file.exists()) return [];
    final raw = await _readWithBak(file);
    if (raw == null) return [];
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final list = data['playlists'] as List? ?? [];
      return list
          .map((e) => Playlist.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      //文件损坏等异常：返回空列表，避免崩溃；下次写入会重建
      return [];
    }
  }

  /// 写入用户歌单（原子写 + `.bak` 备份）
  static Future<void> savePlaylists(List<Playlist> playlists) async {
    try {
      final file = File(await playlistsFilePath());
      const encoder = JsonEncoder.withIndent('  ');
      final data = {'playlists': playlists.map((e) => e.toJson()).toList()};
      await _writeWithBak(file, encoder.convert(data));
    } catch (e) {
      //写歌单失败不致命：下次写入会重试；测试环境无平台通道时走这里
      debugPrint('[storage] 写歌单库失败：$e');
    }
  }

  /// 读取用户歌单**原始 JSON 文本**（JSON 调试页展示用，不经解析，保持原样）；
  /// 文件不存在/读取失败返回 null
  static Future<String?> readPlaylistsRaw() async {
    try {
      final file = File(await playlistsFilePath());
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }
}
