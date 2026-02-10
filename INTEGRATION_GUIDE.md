# NBreader Flutter 阅读引擎 — 接入文档

## 1. 概述

NBreader 是一个纯 Dart/Flutter 实现的电子书阅读引擎，移植自 Android NBReader（Kotlin/C++）。支持 **TXT** 和 **EPUB** 格式，提供完整的排版、分页、翻页动画和阅读设置能力。

### 核心能力

- TXT 文件解析（自动编码检测、章节识别、CJK 文本优化）
- EPUB 文件解析（OPF/NCX/XHTML、内嵌图片）
- 文本排版引擎（分词、断行、分页、样式继承）
- 5 种翻页动画（无、滑动、覆盖、仿真、滚动）
- 阅读设置（字号、行距、字距、边距、夜间模式）
- 阅读进度保存/恢复

### 依赖项

```yaml
dependencies:
  archive: ^4.0.4      # EPUB (ZIP) 解压
  xml: ^6.5.0          # XHTML/OPF/NCX 解析
  path: ^1.9.1         # 路径处理
```

---

## 2. 架构总览

```
┌─────────────────────────────────────────────────┐
│                  你的 App                         │
│  ┌───────────┐  ┌────────────┐  ┌─────────────┐ │
│  │ BookShelf  │  │  ReadPage  │  │ ReadMenu    │ │
│  └───────────┘  └─────┬──────┘  └──────┬──────┘ │
├───────────────────────┼────────────────┼────────┤
│              TextReaderWidget (核心 Widget)       │
├──────────────────────────────────────────────────┤
│  TextEngine ←── TextConfig + TreeTextStyle       │
│  TextModel  ←── FormatPlugin (TxtPlugin/EpubPlugin)│
│  PageAnimation (5种动画)                          │
└──────────────────────────────────────────────────┘
```

**接入只需 3 步：创建 Plugin → 构建 Model → 放入 Widget。**

---

## 3. 最小接入示例

### 3.1 打开书籍并创建 TextModel

```dart
import 'package:nbreader/parser/txt/txt_plugin.dart';
import 'package:nbreader/parser/epub/epub_plugin.dart';
import 'package:nbreader/parser/format_plugin.dart';
import 'package:nbreader/text/engine/text_model.dart';

// 1. 根据文件类型创建插件
FormatPlugin plugin;
if (filePath.endsWith('.epub')) {
  plugin = EpubPlugin();
} else {
  plugin = TxtPlugin();
}

// 2. 打开书籍（异步）
await plugin.openBook(filePath);

// 3. 创建数据模型
final model = TextModel(plugin);

// 获取章节列表（用于目录显示等）
final chapters = model.getChapters(); // List<TextChapter>
```

### 3.2 放入 TextReaderWidget

```dart
import 'package:nbreader/widget/text_reader_widget.dart';
import 'package:nbreader/widget/page_enum.dart';
import 'package:nbreader/text/config/text_config.dart';
import 'package:nbreader/text/style/tree_text_style.dart';
import 'package:nbreader/text/engine/text_page_controller.dart';

class MyReadPage extends StatefulWidget {
  final TextModel model;
  const MyReadPage({super.key, required this.model});

  @override
  State<MyReadPage> createState() => _MyReadPageState();
}

class _MyReadPageState extends State<MyReadPage> {
  final _readerKey = GlobalKey<TextReaderWidgetState>();

  TextConfig _config = TextConfig(
    baseTextStyle: TreeTextStyle(fontSize: 18),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TextReaderWidget(
        key: _readerKey,
        textModel: widget.model,
        textConfig: _config,
        animType: PageAnimType.simulation,
        onPageChanged: (PagePosition pos, PageProgress progress) {
          // 页面变化回调：pos.chapterIndex, progress.pageIndex, progress.pageCount
        },
        onMenuTap: () {
          // 用户点击屏幕中间区域（显示菜单）
        },
      ),
    );
  }
}
```

### 3.3 释放资源

```dart
@override
void dispose() {
  plugin.release();
  super.dispose();
}
```

---

## 4. 核心 API 参考

### 4.1 TextReaderWidget

阅读器核心 Widget，通过 `GlobalKey<TextReaderWidgetState>` 调用实例方法。

**构造参数：**

| 参数 | 类型 | 说明 |
|------|------|------|
| `textModel` | `TextModel` (required) | 数据模型 |
| `textConfig` | `TextConfig?` | 文本配置（字号/颜色/边距等） |
| `animType` | `PageAnimType` | 翻页动画类型，默认 `slide` |
| `onPageChanged` | `Function(PagePosition, PageProgress)?` | 页面变化回调 |
| `onMenuTap` | `Function()?` | 屏幕中间点击回调 |

**实例方法（通过 GlobalKey 调用）：**

```dart
final reader = _readerKey.currentState!;

// 翻页
reader.turnPageAnimated(PageType.next);     // 带动画翻页
reader.turnPageDirect(PageType.previous);   // 无动画翻页

// 跳转
reader.skipChapter(3);                      // 跳转到第4章
reader.skipToPosition(3, 5);                // 跳转到第4章第6页

// 精确位置跳转（推荐用于进度恢复，跨配置变更仍准确）
reader.skipToTextPosition(savedTextPos);    // TextFixedPosition

// 查询状态
reader.isInitialized;                       // bool: 引擎是否已初始化
reader.getPosition();                       // PagePosition?: 当前位置（章节+页码）
reader.getTextPosition();                   // TextFixedPosition?: 精确文本位置
reader.getProgress();                       // PageProgress?: 当前页码进度
reader.hasNextPage();                       // bool
reader.hasPrevPage();                       // bool

// 更新配置（运行时变更字号/行距等，自动精确恢复位置）
reader.updateTextConfig(newConfig);
```

### 4.2 TextConfig — 阅读配置

```dart
TextConfig(
  // 边距（像素）
  marginTop: 16,
  marginBottom: 16,
  marginLeft: 24,
  marginRight: 24,

  // 颜色（ARGB int）
  textColor: 0xFF333333,
  bgColor: 0xFFF5F0E8,

  // 基础文本样式
  baseTextStyle: TreeTextStyle(
    fontSize: 18,           // 字号 (12–36)
    lineSpacePercent: 150,  // 行距百分比 (100–200, 100=单倍, 默认150)
    letterSpacing: 0.5,     // 字间距 (0–5.0, 默认0.5)
    bold: false,
    italic: false,
  ),
)
```

**运行时更新配置：**

```dart
void changeFontSize(int newSize) {
  final config = TextConfig(
    textColor: 0xFF333333,
    bgColor: 0xFFF5F0E8,
    marginLeft: 24,
    marginRight: 24,
    marginTop: 16,
    marginBottom: 16,
    baseTextStyle: TreeTextStyle(
      fontSize: newSize,
      lineSpacePercent: 150,
      letterSpacing: 0.5,
    ),
  );
  _readerKey.currentState?.updateTextConfig(config);
}
```

调用 `updateTextConfig` 后，引擎会自动清除缓存、重新分页，并基于 `TextFixedPosition`（段落+元素级光标）精确恢复阅读位置（而非页码），确保字号/行距/边距变化后位置不偏移。

### 4.3 PageAnimType — 翻页动画

```dart
enum PageAnimType {
  none,       // 无动画（直接切换）
  slide,      // 左右滑动
  cover,      // 覆盖
  simulation, // 仿真翻页（书页卷曲效果）
  scroll,     // 上下滚动
}
```

### 4.4 PagePosition & PageProgress

```dart
class PagePosition {
  final int chapterIndex;  // 章节索引（从 0 开始）
  final int pageIndex;     // 页码索引（从 0 开始）
}

class PageProgress {
  final int pageIndex;     // 当前页码
  final int pageCount;     // 当前章节总页数
  final double totalProgress; // 全书进度（预留）
}
```

### 4.5 TextChapter — 章节信息

```dart
class TextChapter {
  final String url;        // 章节标识（TXT 为内部路径，EPUB 为 XHTML 文件名）
  final String title;      // 章节标题
  final int startIndex;    // 在源文件中的起始偏移
  final int endIndex;      // 结束偏移
}
```

通过 `TextModel.getChapters()` 获取，用于构建目录 UI。

### 4.6 FormatPlugin — 格式插件

```dart
abstract class FormatPlugin {
  Future<void> openBook(String bookPath);
  List<TextChapter> getChapters();
  TextContent? getChapterContent(TextChapter chapter);
  String getEncoding();
  String getLanguage();
  void release();
}
```

内置实现：
- **TxtPlugin** — TXT 文件（自动编码检测，支持 UTF-8/GBK/GB2312/Big5 等）
- **EpubPlugin** — EPUB 文件（含图片解析）

---

## 5. 常见接入场景

### 5.1 阅读进度保存/恢复

使用 `TextFixedPosition`（段落+元素+字符级定位）保存进度，即使用户更改字号/行距/边距后重新打开，仍能精确恢复到之前阅读的位置。

```dart
import 'package:nbreader/text/entity/text_position.dart';

// 保存（使用精确文本位置）
void saveProgress() {
  final textPos = _readerKey.currentState?.getTextPosition();
  if (textPos != null) {
    prefs.setInt('chapter', textPos.chapterIndex);
    prefs.setInt('paragraph', textPos.paragraphIndex);
    prefs.setInt('element', textPos.elementIndex);
    prefs.setInt('char', textPos.charIndex);
  }
}

// 恢复（需在 Widget 初始化完成后调用）
void restoreProgress() {
  final reader = _readerKey.currentState;
  if (reader == null || !reader.isInitialized) {
    Future.delayed(Duration(milliseconds: 200), restoreProgress);
    return;
  }
  final chapter = prefs.getInt('chapter') ?? 0;
  final paragraph = prefs.getInt('paragraph');
  final element = prefs.getInt('element');
  final char = prefs.getInt('char');

  if (paragraph != null && element != null && char != null) {
    reader.skipToTextPosition(TextFixedPosition(
      chapterIndex: chapter,
      paragraphIndex: paragraph,
      elementIndex: element,
      charIndex: char,
    ));
  }
}
```

### 5.2 目录跳转

```dart
final chapters = model.getChapters();

// 构建目录列表
ListView.builder(
  itemCount: chapters.length,
  itemBuilder: (ctx, i) => ListTile(
    title: Text(chapters[i].title),
    onTap: () {
      _readerKey.currentState?.skipChapter(i);
      Navigator.pop(ctx);
    },
  ),
)
```

### 5.3 夜间模式切换

```dart
void toggleNightMode(bool isNight) {
  final config = TextConfig(
    textColor: isNight ? 0xFF999999 : 0xFF333333,
    bgColor: isNight ? 0xFF1A1A1A : 0xFFF5F0E8,
    baseTextStyle: TreeTextStyle(fontSize: _fontSize),
  );
  _readerKey.currentState?.updateTextConfig(config);
}
```

### 5.4 完整设置面板集成

引擎支持的所有可调参数：

```dart
TextConfig buildConfig({
  required bool isNight,
  required int fontSize,        // 12–36
  required int lineSpacePercent, // 100–200
  required double letterSpacing, // 0–5.0
  required int marginH,         // 5–60, 左右边距
  required int marginV,         // 5–60, 上下边距
}) {
  return TextConfig(
    textColor: isNight ? 0xFF999999 : 0xFF333333,
    bgColor: isNight ? 0xFF1A1A1A : 0xFFF5F0E8,
    marginLeft: marginH,
    marginRight: marginH,
    marginTop: marginV,
    marginBottom: marginV,
    baseTextStyle: TreeTextStyle(
      fontSize: fontSize,
      lineSpacePercent: lineSpacePercent,
      letterSpacing: letterSpacing,
    ),
  );
}
```

### 5.5 TxtPlugin 高级配置

```dart
final plugin = TxtPlugin();
// 自定义章节检测正则（可选）
plugin.setConfigure(
  chapterPattern: r'第[零一二三四五六七八九十百千万\d]+[章回节卷集]',
  prologueTitle: '序章',
);
await plugin.openBook(filePath);
```

---

## 6. 手势行为

`TextReaderWidget` 内置手势处理：

- **左 1/3 区域点击** → 上一页（带动画）
- **右 1/3 区域点击** → 下一页（带动画）
- **中间 1/3 区域点击** → 触发 `onMenuTap` 回调
- **左右滑动** → 翻页（跟手动画）

---

## 7. 项目文件结构

```
lib/
├── parser/                    # 格式解析层
│   ├── format_plugin.dart     #   插件抽象接口
│   ├── txt/                   #   TXT 解析
│   │   ├── txt_plugin.dart
│   │   ├── txt_reader.dart
│   │   ├── txt_chapter_detector.dart
│   │   └── plain_text_format.dart
│   ├── epub/                  #   EPUB 解析
│   │   ├── epub_plugin.dart
│   │   ├── xhtml_content_reader.dart
│   │   ├── opf_reader.dart
│   │   ├── ncx_reader.dart
│   │   └── container_reader.dart
│   └── encoding/
│       └── encoding_detector.dart
├── text/                      # 排版引擎层
│   ├── config/text_config.dart
│   ├── style/tree_text_style.dart
│   ├── engine/
│   │   ├── text_engine.dart       # 排版引擎（分页+绘制）
│   │   ├── base_text_engine.dart  # 基础引擎（样式+度量）
│   │   ├── text_model.dart        # 数据模型（章节加载）
│   │   ├── text_page_controller.dart # 页面控制器
│   │   ├── text_canvas.dart       # 绘制画布
│   │   └── text_paint_context.dart # 绘制上下文
│   ├── element/               # 段落内元素（词、图片、空格等）
│   ├── entity/                # 数据实体（页面、行、段落等）
│   ├── tag/                   # 标签类型定义
│   └── util/line_breaker.dart
├── widget/                    # Widget 层
│   ├── text_reader_widget.dart    # 核心阅读 Widget
│   ├── page_enum.dart             # 枚举定义
│   └── anim/                      # 翻页动画实现
│       ├── page_animation.dart
│       ├── slide_page_animation.dart
│       ├── cover_page_animation.dart
│       ├── simulation_page_animation.dart
│       ├── scroll_page_animation.dart
│       └── none_page_animation.dart
├── core/                      # 业务实体（可替换）
│   ├── book_entity.dart
│   └── book_type.dart
├── data/book_repository.dart  # 数据持久化（可替换）
└── ui/                        # 示例 UI（可替换）
    ├── read/read_page.dart
    ├── read/read_menu.dart
    └── bookshelf/bookshelf_page.dart
```

**接入时需要的最小文件集：** `parser/`、`text/`、`widget/` 三个目录。`core/`、`data/`、`ui/` 是示例业务层，可按需替换。

---

## 8. 自定义格式插件

如需支持新格式（如 PDF、MOBI），实现 `FormatPlugin` 接口即可：

```dart
class MyFormatPlugin implements FormatPlugin {
  @override
  Future<void> openBook(String bookPath) async {
    // 解析文件，构建章节结构
  }

  @override
  List<TextChapter> getChapters() {
    // 返回章节列表
    return [
      TextChapter(url: 'ch1', title: '第一章', startIndex: 0, endIndex: 0),
    ];
  }

  @override
  TextContent? getChapterContent(TextChapter chapter) {
    // 返回章节内容（TextTag 列表）
    return TextContent(tags: [
      TextParagraphTag(TextParagraphType.textParagraph),
      TextControlTag(TextControlType.regular, true),
      TextContentTag('这是段落文本内容。'),
      TextParagraphTag(TextParagraphType.endOfSectionParagraph),
    ]);
  }

  @override
  String getEncoding() => 'utf-8';
  @override
  String getLanguage() => 'zh';
  @override
  ImageDataResolver? get imageDataResolver => null;
  @override
  void release() {}
}
```

**TextTag 类型说明：**

- `TextParagraphTag(type)` — 段落开始标记（每个段落必须以此开头）
- `TextControlTag(type, isStart)` — 控制标签（h1-h6、bold、italic 等）
- `TextContentTag(text)` — 文本内容
- `TextImageTag(id, imageData: bytes)` — 图片
- `TextFixedHSpaceTag(length)` — 固定宽度空格

章节内容必须以 `TextParagraphTag(endOfSectionParagraph)` 结尾。

---

## 9. 注意事项

1. **TextReaderWidget 必须有明确的尺寸约束**（放在 `Expanded`、`SizedBox` 等容器中），引擎需要知道视口大小来分页。

2. **`updateTextConfig` 会自动重新分页**，无需手动刷新。内部会清除元素宽度缓存、重建页面控制器并恢复阅读位置。

3. **EPUB 图片是异步解码的**。首次渲染时显示占位框，解码完成后自动重新分页并刷新显示。

4. **`plugin.release()` 必须在不再使用时调用**，释放文件缓存和内存。

5. **CJK 文本自动优化**：格式检测器会识别中文/日文/韩文内容，自动使用逐行分段策略（`breakParagraphAtNewLine`），无需手动配置。
