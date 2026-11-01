import 'dart:convert';

/// 可自定义颜色的区域清单（v1.0 主题定制"多数地方"）
///
/// 每个枚举值对应一个 UI 区域；用户自定义后存 ARGB int，
/// 未自定义（null）时使用明暗模式默认色。
enum PaletteItem {
  /// 页面主背景
  background,

  /// 列表项/卡片背景
  surface,

  /// 主文字（歌名等正文）
  textPrimary,

  /// 次文字（时长、说明、灰字）
  textSecondary,

  /// 强调色（当前歌高亮、进度条、按钮；即主题色）
  accent,

  /// 通用图标色（未单独指定颜色的图标兜底用）
  icon,

  /// 搜索图标（主页/搜索页放大镜）
  iconSearch,

  /// 上一首图标
  iconPrevious,

  /// 下一首图标
  iconNext,

  /// 播放/暂停图标
  iconPlayPause,

  /// 播放模式图标（循环/随机/单曲）
  iconMode,

  /// 播放队列/排序图标
  iconQueue,

  /// 更多操作图标（三点）
  iconMore,

  /// 设置图标（齿轮）
  iconSettings,

  /// 添加图标（加号，歌单等）
  iconAdd,

  /// 收藏星标色（v1.0 状态色开放，默认 amber 琥珀）
  favoriteStar,

  /// 收藏红（"我的收藏"入口等，默认红色）
  favoriteRed,

  /// 当前播放歌曲高亮色（默认 = 强调色）
  currentHighlight,

  /// 播放队列"被标记下一首播放"的标记色（v1.1-3，默认 = 主题色）
  queueNext,

  /// AppBar 背景
  appBar,

  /// 底部播放栏背景
  bottomBar,

  /// 抽屉背景
  drawer,

  /// 弹窗/对话框背景
  dialog,

  /// 提示条背景（SnackBar/浮层提示，v1.0 第三阶段修复：不再固定黑色）
  snackbarBg,

  /// 提示条文字（SnackBar/浮层提示文字，可自定义）
  snackbarText,

  /// 分割线颜色
  divider,

  /// 悬浮定位按钮背景（v1.0 第四阶段：主页/歌单页"定位当前播放歌曲"按钮）
  locateButtonBg,

  /// 悬浮定位按钮文字/图标（v1.0 第四阶段）
  locateButtonText,

  /// JSON 查找弹窗背景（v1.0 第四阶段：JSON 页搜索弹窗）
  jsonSearchBg,

  /// JSON 查找弹窗文字（v1.0 第四阶段）
  jsonSearchText,

  /// JSON 一级高亮关键词背景（v1.1-3：所有查找到的关键词底色；
  /// 默认 = 主题色）
  jsonHighlight1Bg,

  /// JSON 一级高亮关键词文字（默认 = 主题色反色）
  jsonHighlight1Text,

  /// JSON 二级高亮关键词背景（当前选中的匹配；默认 = 主题色）
  jsonHighlight2Bg,

  /// JSON 二级高亮关键词文字（默认 = 主题色反色）
  jsonHighlight2Text,
}

/// 单个页面 / 歌单 / 播放源的独立背景配置（v1.1-3）
///
/// 语义：条目存在 = 该作用范围**被单独设置**（覆盖全局默认背景图与遮罩）；
/// 移除当前背景 = 删除整个条目 → 回退全局背景。
class PageBackgroundConfig {
  PageBackgroundConfig({
    this.imagePath,
    this.maskDay = 0.0,
    this.maskNight = 0.30,
  });

  /// 该范围使用的背景图片绝对路径（null = 理论上不应出现，防御处理回退全局）
  String? imagePath;

  /// 遮罩浓度（日间白遮罩 0.0 透明 ~ 1.0 全白，默认 0.0 = 不加遮罩）
  double maskDay;

  /// 遮罩浓度（夜间黑遮罩 0.0 透明 ~ 1.0 全黑，默认 0.30）
  double maskNight;

  Map<String, dynamic> toJson() => {
        'imagePath': imagePath,
        'maskDay': maskDay,
        'maskNight': maskNight,
      };

  factory PageBackgroundConfig.fromJson(Map<String, dynamic> data) {
    final c = PageBackgroundConfig();
    c.imagePath = data['imagePath'] as String?;
    final day = (data['maskDay'] as num?)?.toDouble();
    if (day != null) c.maskDay = day.clamp(0.0, 1.0);
    final night = (data['maskNight'] as num?)?.toDouble();
    if (night != null) c.maskNight = night.clamp(0.0, 1.0);
    return c;
  }
}

/// 主题调色板：可自定义颜色 + 背景图路径。
///
/// 只保存**已自定义**的项（null = 跟随明暗默认色）；
/// 序列化只存非空项，避免污染偏好文件。
class ThemePalette {
  /// SharedPreferences 中的存储 key（JSON 字符串）
  static const prefKey = 'theme_palette';

  /// 默认构造（类声明了 factory 构造后需显式声明，否则隐式默认构造失效）
  ThemePalette();

  /// 已自定义的颜色（item -> ARGB int）
  final Map<PaletteItem, int> _colors = {};

  /// 背景图片绝对路径（null = 未启用背景图）
  String? backgroundImagePath;

  /// 背景图遮罩不透明度（**夜间模式**，0.0 无遮罩 ~ 1.0 全黑，默认 0.30）
  double backgroundOverlayAlphaDark = 0.30;

  /// 背景图遮罩不透明度（**日间模式**，0.0 无遮罩 ~ 1.0 全黑，默认 0.0。
  /// 日间浅色 UI 再叠加黑色遮罩会观感发黑，默认不加遮罩）
  double backgroundOverlayAlphaLight = 0.0;

  /// **抽屉栏遮罩浓度（夜间模式）**：启用背景图时抽屉背景不透明度，
  /// 0.0 全透明（背景图直接透出）~ 1.0 全黑（等同未设置背景图）。
  /// 默认 0.65：比旧"50% 实色"更不透明，保证抽屉文字清晰。
  double drawerOverlayAlphaDark = 0.65;

  /// **抽屉栏遮罩浓度（日间模式）**：启用背景图时抽屉背景不透明度，
  /// 0.0 全透明 ~ 1.0 全白（等同未设置背景图）。
  double drawerOverlayAlphaLight = 0.65;

  /// **悬浮定位按钮遮罩浓度**（v1.0 四阶段，用户 2026-10-27 调整）：
  /// 单档 0.0 ~ 1.0。0 = 主题色几近透明（露出底色）；1 = 完全不透明
  /// （纯主题色；夜间模式遮罩色为"偏灰的主题色"）。
  double locateOverlayAlpha = 0.0;

  /// **逐页背景配置**（v1.1-3）：页面 Key → 独立背景（覆盖全局默认）。
  /// Key 取值见 [ThemePalette.pageKeys]；播放队列页支持源级覆盖
  /// （`queue:allSongs` / `queue:favorites` / `queue:pl:<歌单id>`，
  ///  回退链：源专属 → `queue`（全部播放源）→ 全局）。
  final Map<String, PageBackgroundConfig> perPageBackgrounds = {};

  /// **逐歌单背景配置**（v1.1-3）：歌单 id → 独立背景（覆盖全局默认；
  /// 回退链：`pl:<歌单id>` → 全局）。
  final Map<String, PageBackgroundConfig> perPlaylistBackgrounds = {};

  /// 页面 Key 常量（设置各页面背景图片页的板块与 AppBackground 传参共用，
  /// 保证写配置与取配置使用同一套 Key）
  static const pageKeyHome = 'home';
  static const pageKeyFavorites = 'favorites';
  static const pageKeyPlayer = 'player';
  static const pageKeyQueue = 'queue';
  static const pageKeySearch = 'search';
  static const pageKeySettingsPages = 'settingsPages';
  static const pageKeyJsonData = 'jsonData';
  static const pageKeyAbout = 'about';

  /// 播放队列"源级"Key 前缀：`queue:allSongs` / `queue:favorites` /
  /// `queue:pl:<歌单id>`（回退到 [pageKeyQueue] 再回退全局）
  static const queueSourcePrefix = 'queue:';
  static const queueSourceAllSongs = 'queue:allSongs';
  static const queueSourceFavorites = 'queue:favorites';

  /// 歌单背景 Key 前缀：`pl:<歌单id>`（回退到全局）
  static const playlistPrefix = 'pl:';

  /// 生成播放队列源级 Key
  static String queueSourceKey(String sourceName, String? playlistId) {
    if (sourceName == 'allSongs') return queueSourceAllSongs;
    if (sourceName == 'favorites') return queueSourceFavorites;
    //playlist 源：queue:pl:<歌单id>
    return '${queueSourcePrefix}pl:${playlistId ?? ''}';
  }

  /// 生成歌单页 Key
  static String playlistKey(String playlistId) =>
      '$playlistPrefix$playlistId';

  /// 独立可自定义的具体图标项（用于图标取色回落：具体项 ?? 通用 icon）
  static const List<PaletteItem> specificIconItems = [
    PaletteItem.iconSearch,
    PaletteItem.iconPrevious,
    PaletteItem.iconNext,
    PaletteItem.iconPlayPause,
    PaletteItem.iconMode,
    PaletteItem.iconQueue,
    PaletteItem.iconMore,
    PaletteItem.iconSettings,
    PaletteItem.iconAdd,
  ];

  /// 取某区域的自定义颜色（null = 未自定义）
  int? colorOf(PaletteItem item) => _colors[item];

  /// 图标取色：具体图标项的自定义 ?? 通用图标项的自定义 ?? null。
  /// （旧版本只有"图标"一项，迁移后所有具体项都继承它；用户可再逐个改）
  int? iconColorOf(PaletteItem item) {
    if (specificIconItems.contains(item)) {
      return _colors[item] ?? _colors[PaletteItem.icon];
    }
    return _colors[item];
  }

  /// 自定义某区域颜色
  void setColor(PaletteItem item, int argb) => _colors[item] = argb;

  /// 清除某区域自定义（恢复明暗默认）
  void clearColor(PaletteItem item) => _colors.remove(item);

  /// 是否启用背景图
  bool get hasBackgroundImage => backgroundImagePath != null;

  /// 恢复默认（v1.0 第四阶段，用户 2026-10-27 调整）：
  /// **只清空全部自定义颜色**；各遮罩浓度（背景/抽屉/定位按钮）属于
  /// 背景图片页的设置，恢复主题时**保持不变**；背景图路径也不清除。
  void resetColors() {
    _colors.clear();
  }

  /// 序列化（只存非空项）
  String toJson() => jsonEncode({
        'colors': {
          for (final e in _colors.entries) e.key.name: e.value,
        },
        'backgroundImagePath': backgroundImagePath,
        'backgroundOverlayAlphaDark': backgroundOverlayAlphaDark,
        'backgroundOverlayAlphaLight': backgroundOverlayAlphaLight,
        'drawerOverlayAlphaDark': drawerOverlayAlphaDark,
        'drawerOverlayAlphaLight': drawerOverlayAlphaLight,
        'locateOverlayAlpha': locateOverlayAlpha,
        if (perPageBackgrounds.isNotEmpty)
          'perPageBackgrounds': {
            for (final e in perPageBackgrounds.entries)
              e.key: e.value.toJson(),
          },
        if (perPlaylistBackgrounds.isNotEmpty)
          'perPlaylistBackgrounds': {
            for (final e in perPlaylistBackgrounds.entries)
              e.key: e.value.toJson(),
          },
      });

  /// 反序列化；解析失败返回空调色板（不崩溃）
  factory ThemePalette.fromJson(String raw) {
    final p = ThemePalette();
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final colors = data['colors'] as Map<String, dynamic>?;
      if (colors != null) {
        for (final e in colors.entries) {
          PaletteItem? item;
          for (final x in PaletteItem.values) {
            if (x.name == e.key) {
              item = x;
              break;
            }
          }
          if (item != null) {
            final v = (e.value as num?)?.toInt();
            if (v != null) p._colors[item] = v;
          }
        }
      }
      p.backgroundImagePath = data['backgroundImagePath'] as String?;
      //夜间/日间遮罩浓度（越界收敛；兼容旧版单一 backgroundOverlayAlpha）
      final dark = (data['backgroundOverlayAlphaDark'] as num?)?.toDouble();
      final old = (data['backgroundOverlayAlpha'] as num?)?.toDouble();
      p.backgroundOverlayAlphaDark =
          (dark ?? old ?? p.backgroundOverlayAlphaDark).clamp(0.0, 1.0);
      final light = (data['backgroundOverlayAlphaLight'] as num?)?.toDouble();
      p.backgroundOverlayAlphaLight =
          (light ?? p.backgroundOverlayAlphaLight).clamp(0.0, 1.0);
      //抽屉栏遮罩浓度（日/夜分开；旧版本无此字段 → 用默认值）
      final drawerDark =
          (data['drawerOverlayAlphaDark'] as num?)?.toDouble();
      p.drawerOverlayAlphaDark =
          (drawerDark ?? p.drawerOverlayAlphaDark).clamp(0.0, 1.0);
      final drawerLight =
          (data['drawerOverlayAlphaLight'] as num?)?.toDouble();
      p.drawerOverlayAlphaLight =
          (drawerLight ?? p.drawerOverlayAlphaLight).clamp(0.0, 1.0);
      //悬浮定位按钮遮罩浓度（v1.0 四阶段：日/夜两档合并为单档）
      final locate = (data['locateOverlayAlpha'] as num?)?.toDouble();
      if (locate != null) {
        p.locateOverlayAlpha = locate.clamp(0.0, 1.0);
      }
      //逐页背景（v1.1-3：损坏条目跳过，不阻断整份解析）
      final perPage = data['perPageBackgrounds'] as Map<String, dynamic>?;
      if (perPage != null) {
        for (final e in perPage.entries) {
          final raw = e.value;
          if (raw is Map<String, dynamic>) {
            p.perPageBackgrounds[e.key] =
                PageBackgroundConfig.fromJson(raw);
          }
        }
      }
      final perPlaylist =
          data['perPlaylistBackgrounds'] as Map<String, dynamic>?;
      if (perPlaylist != null) {
        for (final e in perPlaylist.entries) {
          final raw = e.value;
          if (raw is Map<String, dynamic>) {
            p.perPlaylistBackgrounds[e.key] =
                PageBackgroundConfig.fromJson(raw);
          }
        }
      }
    } catch (_) {
      //损坏数据：返回空调色板
    }
    return p;
  }
}
