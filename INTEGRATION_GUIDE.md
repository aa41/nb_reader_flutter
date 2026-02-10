# NBreader Flutter 阅读引擎 — 接入文档

## 1. 概述

NBreader 是一个纯 Dart/Flutter 实现的电子书阅读引擎，移植自 Android NBReader（Kotlin/C++）。支持 **TXT**、**EPUB** 和 **Markdown** 格式，提供完整的排版、分页、翻页动画和阅读设置能力。

### 核心能力

- TXT 文件解析（自动编码检测 UTF-8/GBK/GB2312/Big5、章节识别、CJK 文本优化）
- EPUB 文件解析（OPF/NCX/XHTML、内嵌图片、单文件多章节支持）
- Markdown 文件解析（语法高亮、表格渲染、本地/网络图片、引用块、列表等）
- 文本排版引擎（分词、断行、分页、样式继承树）
- 5 种翻页动画（无、滑动、覆盖、仿真卷曲、滚动）
- 阅读设置（字号、行距、字距、边距、夜间模式、壁纸）
- 阅读进度精确保存/恢复（基于段落+元素+字符级定位）
- Header/Footer 自动绘制（章节标题、页码、时间）

### 依赖项

```yaml
dependencies:
  archive: ^4.0.4      # EPUB (ZIP) 解压
  xml: ^6.5.0          # XHTML/OPF/NCX 解析
  path: ^1.9.1         # 路径处理
  markdown: ^7.2.2     # Markdown AST 解析
  http: ^1.2.0         # 网络图片加载（Markdown）
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
│  TextModel  ←── FormatPlugin                     │
│                  ├── TxtPlugin                   │
│                  ├── EpubPlugin                  │
│                  └── MarkdownPlugin              │
│  PageAnimation (5种动画)                          │
└──────────────────────────────────────────────────┘
```

**接入只需 3 步：创建 Plugin → 构建 Model → 放入 Widget。**

### 数据流

```
FormatPlugin → TextTag[] → TextModel → TextChapterCursor
→ TextParagraphCursor (解码 TextTag 为 TextElement[])
→ TextEngine (分页为 TextPage[]) → TextCanvas (绘制)
```

---

## 3. 最小接入示例

### 3.1 打开书籍并创建 TextModel

```dart
import 'package:nbreader/parser/txt/txt_plugin.dart';
import 'package:nbreader/parser/epub/epub_plugin.dart';
import 'package:nbreader/parser/markdown/markdown_plugin.dart';
import 'package:nbreader/parser/format_plugin.dart';
import 'package:nbreader/text/engine/text_model.dart';

// 1. 根据文件类型创建插件
FormatPlugin plugin;
final ext = filePath.split('.').last.toLowerCase();
switch (ext) {
  case 'epub':
    plugin = EpubPlugin();
    break;
  case 'md':
  case 'markdown':
    plugin = MarkdownPlugin();
    break;
  default:
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
  final List<TextChapter> chapters;
  const MyReadPage({super.key, required this.model, required this.chapters});

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
        // Header 显示章节标题需要传入章节列表
        chapters: widget.chapters,
        // Footer 显示时间
        timeStr: '21:05',
        // 安全区域（状态栏/导航栏），用于 header/footer 位置计算
        safeArea: MediaQuery.of(context).padding,
        onPageChanged: (PagePosition pos, PageProgress progress) {
          // 页面变化回调
        },
        onMenuTap: () {
          // 用户点击屏幕中间区域（显示菜单）
        },
      ),
    );
  }
}
```

> **重要**：`TextReaderWidget` 必须有明确的尺寸约束（如放在 `Scaffold.body`、`Expanded`、`SizedBox` 中），引擎需要视口尺寸来分页。
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
| `chapters` | `List<TextChapter>` | 章节列表（用于 Header 显示章节标题） |
| `timeStr` | `String` | 时间字符串（用于 Footer 显示时间） |
| `safeArea` | `EdgeInsets` | 安全区域内边距（状态栏/导航栏） |

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

// 切换翻页动画类型
reader.setAnimType(PageAnimType.cover);
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

  // 壁纸路径（设置后 bgColor 作为底色，壁纸覆盖在上层）
  wallpaperPath: null,  // '/path/to/wallpaper.jpg'

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

### 4.5 TextFixedPosition — 精确文本位置

用于阅读进度保存/恢复，基于段落+元素+字符级定位，不受配置变更（字号/行距/边距）影响。

```dart
class TextFixedPosition {
  final int chapterIndex;    // 章节索引
  final int paragraphIndex;  // 段落索引
  final int elementIndex;    // 元素索引（段落内的第几个元素）
  final int charIndex;       // 字符索引（元素内的第几个字符）
}
```

### 4.6 TextChapter — 章节信息

```dart
class TextChapter {
  final String url;        // 章节标识（TXT 为内部路径，EPUB 为 XHTML 文件名）
  final String title;      // 章节标题
  final int startIndex;    // 在源文件中的起始偏移
  final int endIndex;      // 结束偏移
}
```

通过 `TextModel.getChapters()` 获取，用于构建目录 UI。

### 4.7 TextModel — 数据模型

```dart
final model = TextModel(plugin);

model.getChapterCount();           // int: 章节总数
model.getChapters();               // List<TextChapter>: 章节列表（不可变）
model.getChapter(index);           // TextChapter: 获取指定章节
model.getChapterContent(index);    // TextContent?: 获取章节内容
model.getChapterCursor(index);     // TextChapterCursor: 获取章节光标（带 LRU 缓存，5 章）
model.getLanguage();               // String: 语言
model.clearCache();                // 清除光标缓存（配置变更时自动调用）
```

---

## 5. 格式插件详解

### 5.1 FormatPlugin — 抽象接口

```dart
abstract class FormatPlugin {
  Future<void> openBook(String bookPath);
  List<TextChapter> getChapters();
  TextContent? getChapterContent(TextChapter chapter);
  String getEncoding();
  String getLanguage();
  ImageDataResolver? get imageDataResolver => null;
  void release();
}

typedef ImageDataResolver = Uint8List? Function(String imagePath);
```

### 5.2 TxtPlugin — TXT 格式

- 自动编码检测：UTF-8、GBK、GB2312、Big5 等
- 自动章节识别：正则匹配「第X章/回/节/卷/集」
- CJK 文本优化：逐字符断行
- 格式探测：自动识别空行分段 vs 换行分段

```dart
final plugin = TxtPlugin();

// 可选：自定义章节检测正则
plugin.setConfigure(
  chapterPattern: r'第[零一二三四五六七八九十百千万\d]+[章回节卷集]',
  prologueTitle: '序章',
);

await plugin.openBook(filePath);
```

### 5.3 EpubPlugin — EPUB 格式

- 完整解析流程：`container.xml` → OPF → NCX → XHTML
- 支持内嵌图片（PNG/JPEG/GIF/SVG）
- 支持单文件多章节（通过 `#fragment` 锚点拆分）
- NCX 不完整时自动回退到 Spine 顺序 + 标题提取

```dart
final plugin = EpubPlugin();
await plugin.openBook(filePath);

// 获取元数据
final title = plugin.title;           // String?: 书名
final author = plugin.author;         // String?: 作者
final cover = plugin.getCoverImage(); // Uint8List?: 封面图片数据
```

EPUB 图片处理流程：
1. `XhtmlContentReader` 解析时通过 `ImageDataResolver` 同步加载 EPUB 内嵌图片
2. 如果图片尚未解码，显示灰色占位框
3. `TextCanvas` 异步解码图片，完成后触发 `onImageDecoded` 回调
4. Widget 自动重新分页并刷新显示

### 5.4 MarkdownPlugin — Markdown 格式

- 按 `#` / `##` 标题自动拆分章节
- 支持 GitHub Flavored Markdown (GFM)
- 代码块语法高亮（支持 Dart/Java/Kotlin/JS/TS/Python/C/C++/Go/Rust/Swift/SQL 等）
- 表格渲染（Canvas 绘制为图片 / 纯文本回退）
- 本地图片加载（相对于 .md 文件目录解析路径，支持 `./` 和 `../`）
- 网络图片异步下载

```dart
final plugin = MarkdownPlugin();
await plugin.openBook(filePath);
```

**支持的 Markdown 元素：**

| 元素 | 语法 | 渲染效果 |
|------|------|----------|
| 标题 | `# ~ ######` | h1–h6，字号递减 + 加粗 |
| 粗体 | `**text**` | 加粗 |
| 斜体 | `*text*` | 斜体 |
| 删除线 | `~~text~~` | 删除线 |
| 行内代码 | `` `code` `` | 等宽字体 + 灰色背景 |
| 代码块 | ` ``` ` | 等宽字体 + 语法高亮 + 灰色背景 |
| 引用块 | `>` | 斜体 + 左缩进 + 灰色文字 |
| 无序列表 | `- / * / +` | 圆点前缀 |
| 有序列表 | `1.` | 数字前缀 |
| 任务列表 | `- [x] / - [ ]` | ☑ / ☐ 前缀 |
| 图片 | `![alt](src)` | 内嵌图片（本地/网络） |
| 链接 | `[text](url)` | 展平为纯文本 |
| 水平线 | `---` | 居中分隔符 `· · ·` |
| 表格 | GFM 表格语法 | Canvas 图片 / 文本回退 |

**代码高亮支持的语言：**
`dart`, `java`, `kotlin`, `javascript`, `typescript`, `python`, `c`, `cpp`, `go`, `rust`, `swift`, `sql`, `json`, `bash`, `ruby`, `yaml`, `html`, `xml`

---

## 6. 常见接入场景

### 6.1 阅读进度保存/恢复

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

### 6.2 目录跳转

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

### 6.3 夜间模式切换

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

### 6.4 完整设置面板集成

引擎支持的所有可调参数：

```dart
TextConfig buildConfig({
  required bool isNight,
  required int fontSize,        // 12–36
  required int lineSpacePercent, // 100–200
  required double letterSpacing, // 0–5.0
  required int marginH,         // 5–60, 左右边距
  required int marginV,         // 5–60, 上下边距
  String? wallpaperPath,        // 壁纸路径，null 表示纯色背景
}) {
  return TextConfig(
    textColor: isNight ? 0xFF999999 : 0xFF333333,
    bgColor: isNight ? 0xFF1A1A1A : 0xFFF5F0E8,
    wallpaperPath: wallpaperPath,
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

### 6.5 EPUB 元数据提取

```dart
final plugin = EpubPlugin();
await plugin.openBook(filePath);

final title = plugin.title ?? '未知';
final author = plugin.author ?? '未知';

// 封面图片
final coverBytes = plugin.getCoverImage();
if (coverBytes != null) {
  Image.memory(coverBytes);
}
```

### 6.6 Header/Footer 自定义

`TextReaderWidget` 内置了 Header（章节标题）和 Footer（页码 + 时间）的 Canvas 绘制。通过构造参数控制：

```dart
TextReaderWidget(
  // ...
  chapters: chapters,               // 传入章节列表 → Header 显示当前章节标题
  timeStr: '21:05',                 // 传入时间字符串 → Footer 右侧显示时间
  safeArea: MediaQuery.of(context).padding, // 安全区域，避免被状态栏遮挡
)
```

Header/Footer 的边距会自动从 `TextConfig.marginTop/Bottom` 中额外扣除，不会与正文重叠。不传 `chapters` 和 `timeStr` 则不显示。

### 6.7 沉浸模式（全屏阅读）

```dart
import 'package:flutter/services.dart';

// 进入阅读页：隐藏状态栏和导航栏
SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

// 显示菜单时：恢复系统 UI
SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

// 退出阅读页：恢复
SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
```

### 6.8 Markdown 表格预渲染

Markdown 中的表格可通过 `TableImageRenderer` 预渲染为 PNG 图片：

```dart
import 'package:nbreader/parser/markdown/table_image_renderer.dart';

final pngBytes = await TableImageRenderer.render(
  headers: ['列1', '列2', '列3'],
  rows: [['A', 'B', 'C'], ['D', 'E', 'F']],
  maxWidth: 360.0,
);

// 传入 MarkdownReader（key = 'table_{headers.join("|") }_{rows.length}'）
final reader = MarkdownReader(
  basePath: '/path/to/md/dir',
  tableImages: { 'table_列1|列2|列3_2': pngBytes! },
);
```

如果不传 `tableImages`，表格会自动回退为纯文本渲染（表头加粗 + 竖线分隔）。

### 6.9 根据文件扩展名自动选择插件

```dart
import 'package:nbreader/core/book_type.dart';

FormatPlugin createPlugin(String filePath) {
  final ext = filePath.split('.').last.toLowerCase();
  final type = BookType.fromExtension('.$ext');
  switch (type) {
    case BookType.epub:
      return EpubPlugin();
    case BookType.markdown:
      return MarkdownPlugin();
    case BookType.txt:
    default:
      return TxtPlugin();
  }
}
```

`BookType.fromExtension()` 支持：`.txt` → TXT，`.epub` → EPUB，`.md` / `.markdown` → Markdown。

---

## 7. 手势行为

`TextReaderWidget` 内置手势处理：

- **左 1/3 区域点击** → 上一页（带动画）
- **右 1/3 区域点击** → 下一页（带动画）
- **中间 1/3 区域点击** → 触发 `onMenuTap` 回调
- **左右滑动** → 跟手翻页动画（滑动超过 1/3 宽度或速度 > 300px/s 翻页成功，否则回弹）

---

## 8. 项目文件结构

```
lib/
├── parser/                    # 格式解析层
│   ├── format_plugin.dart     #   插件抽象接口 + ImageDataResolver
│   ├── txt/                   #   TXT 解析
│   │   ├── txt_plugin.dart    #     TXT 插件入口
│   │   ├── txt_reader.dart    #     文本 → TextTag 解析
│   │   ├── txt_chapter_detector.dart  # 章节检测
│   │   └── plain_text_format.dart     # 格式探测（空行/换行分段）
│   ├── epub/                  #   EPUB 解析
│   │   ├── epub_plugin.dart   #     EPUB 插件入口
│   │   ├── xhtml_content_reader.dart  # XHTML → TextTag
│   │   ├── opf_reader.dart    #     OPF（manifest/spine/metadata）
│   │   ├── ncx_reader.dart    #     NCX（目录）
│   │   └── container_reader.dart      # container.xml
│   ├── markdown/              #   Markdown 解析
│   │   ├── markdown_plugin.dart       # Markdown 插件入口
│   │   ├── markdown_reader.dart       # AST → TextTag
│   │   ├── code_highlighter.dart      # 语法高亮 tokenizer
│   │   └── table_image_renderer.dart  # 表格 → PNG 渲染
│   └── encoding/
│       └── encoding_detector.dart     # 编码检测（UTF-8/GBK/Big5）
├── text/                      # 排版引擎层
│   ├── config/text_config.dart        # 阅读配置
│   ├── style/
│   │   ├── tree_text_style.dart       # 样式树
│   │   └── text_alignment_type.dart   # 对齐方式枚举
│   ├── engine/
│   │   ├── text_engine.dart       # 排版引擎（分页+绘制）
│   │   ├── base_text_engine.dart  # 基础引擎（样式+度量）
│   │   ├── text_model.dart        # 数据模型（章节加载 + LRU 缓存）
│   │   ├── text_page_controller.dart  # 页面控制器（翻页+跳转）
│   │   ├── text_canvas.dart       # 绘制画布 + 图片异步解码缓存
│   │   ├── text_paint_context.dart    # 绘制上下文（字体度量）
│   │   └── cursor/                    # 光标层级
│   │       ├── text_chapter_cursor.dart    # 章节光标
│   │       ├── text_paragraph_cursor.dart  # 段落光标（TextTag → TextElement）
│   │       └── text_word_cursor.dart       # 单词光标（精确定位）
│   ├── element/               # 段落内元素
│   │   ├── text_element.dart          # 基类 + 空格/缩进常量
│   │   ├── text_word_element.dart     # 单词/字符元素
│   │   ├── text_image_element.dart    # 图片元素
│   │   ├── text_control_element.dart  # 控制元素（样式切换）
│   │   ├── text_style_element.dart    # CSS 样式元素
│   │   └── text_fixed_hspace_element.dart # 固定宽度空格
│   ├── entity/                # 数据实体
│   │   ├── text_chapter.dart      # 章节信息
│   │   ├── text_content.dart      # 章节内容（TextTag 列表）
│   │   ├── text_page.dart         # 页面（起止光标）
│   │   ├── text_line.dart         # 行信息（宽高、间距、缩进）
│   │   ├── text_element_area.dart # 元素绘制区域
│   │   ├── text_position.dart     # 位置（抽象 + TextFixedPosition）
│   │   ├── text_paragraph.dart    # 段落信息
│   │   └── text_metrics.dart      # 度量信息
│   ├── tag/                   # 标签定义
│   │   ├── text_tag.dart          # TextTag 类族
│   │   └── text_tag_type.dart     # 类型常量
│   └── util/
│       └── line_breaker.dart      # CJK 断行工具
├── utils/
│   └── html_unescape.dart         # HTML 实体解码工具
├── widget/                    # Widget 层
│   ├── text_reader_widget.dart    # 核心阅读 Widget
│   ├── text_page_painter.dart     # CustomPainter（直接绘制）
│   ├── page_enum.dart             # 枚举定义（PageType, PageAnimType）
│   └── anim/                      # 翻页动画实现
│       ├── page_animation.dart        # 基类 + 手势/缓存/状态管理
│       ├── anim_page_painter.dart     # 动画 CustomPainter
│       ├── slide_page_animation.dart  # 滑动
│       ├── cover_page_animation.dart  # 覆盖
│       ├── simulation_page_animation.dart # 仿真卷曲
│       ├── scroll_page_animation.dart # 滚动
│       └── none_page_animation.dart   # 无动画
├── core/                      # 业务实体（可替换）
│   ├── book_entity.dart           # 书籍实体
│   └── book_type.dart             # 格式枚举（txt/epub/markdown）
├── data/
│   └── book_repository.dart       # SharedPreferences 持久化（可替换）
└── ui/                        # 示例 UI（可替换）
    ├── bookshelf/bookshelf_page.dart
    └── read/
        ├── read_page.dart         # 完整阅读页示例
        ├── read_menu.dart         # 菜单/设置面板
        └── catalog_drawer.dart    # 目录抽屉
```

**接入时需要的最小文件集：** `parser/`、`text/`、`widget/`、`utils/` 四个目录。`core/`、`data/`、`ui/` 是示例业务层，可按需替换。

---

## 9. 自定义格式插件

如需支持新格式（如 PDF、MOBI），实现 `FormatPlugin` 接口即可：

```dart
class MyFormatPlugin implements FormatPlugin {
  @override
  Future<void> openBook(String bookPath) async {
    // 解析文件，构建章节结构
  }

  @override
  List<TextChapter> getChapters() {
    return [
      TextChapter(url: 'ch1', title: '第一章', startIndex: 0, endIndex: 0),
    ];
  }

  @override
  TextContent? getChapterContent(TextChapter chapter) {
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

### 9.1 TextTag 类型说明

| 类型 | 说明 |
|------|------|
| `TextParagraphTag(type)` | 段落开始标记（每个段落必须以此开头） |
| `TextControlTag(type, isStart)` | 控制标签（h1-h6、bold、italic 等） |
| `TextContentTag(text)` | 文本内容 |
| `TextImageTag(id, imageData: bytes)` | 图片（id 为唯一标识） |
| `TextCssStyleTag(...)` | CSS 样式（颜色、对齐等） |
| `TextStyleCloseTag.instance` | 关闭最近的样式标签 |
| `TextFixedHSpaceTag(length)` | 固定宽度空格 |

### 9.2 TextControlType 常量

| 常量 | 值 | 说明 |
|------|---|------|
| `regular` | 0 | 普通文本 |
| `h1` ~ `h6` | 1–6 | 标题（字号递减 + 加粗 + 段前后间距） |
| `strong` / `bold` | 7/8 | 加粗 |
| `emphasis` / `italic` | 9/10 | 斜体 |
| `code` / `tt` | 11/12 | 行内代码（等宽字体 + 灰色背景） |
| `cite` | 16 | 引用块（斜体 + 左缩进 + 灰色文字） |
| `superscript` / `subscript` | 17/18 | 上标/下标（70% 字号） |
| `strike` | 21 | 删除线 |
| `preformatted` | 22 | 代码块（等宽字体 + 85% 字号 + 灰色背景） |
| `title` | 24 | TXT 章节标题 |

### 9.3 TextParagraphType 常量

| 常量 | 值 | 说明 |
|------|---|------|
| `textParagraph` | 0 | 普通文本段落 |
| `emptyLineParagraph` | 2 | 空行（段间距） |
| `endOfSectionParagraph` | 5 | 章节结束标记（**每章必须以此结尾**） |

### 9.4 章节内容构建模式

每个段落的 Tag 序列遵循固定模式：

```
TextParagraphTag(textParagraph)        ← 段落开始
TextControlTag(type, true)             ← 开启样式
  TextContentTag('文本内容')            ← 内容
  TextCssStyleTag(color: 0xFFFF0000)   ← 可选：额外样式
    TextContentTag('红色文本')
  TextStyleCloseTag                    ← 关闭额外样式
TextControlTag(type, false)            ← 关闭样式
...
TextParagraphTag(endOfSectionParagraph) ← 章节结束
```

---

## 10. 图片处理机制

### 10.1 同步加载（EPUB 内嵌图片 / Markdown 本地图片）

- `FormatPlugin.getChapterContent()` 中通过 `ImageDataResolver` 同步获取图片字节
- 图片数据存储在 `TextImageTag.imageData` 中
- 渲染时由 `TextCanvas` 异步解码为 `ui.Image`

### 10.2 异步加载（网络图片）

- `TextImageTag.imageData` 为 `null`，但 `id` 是网络 URL
- `TextCanvas._ImageDecodeCache` 自动下载并解码
- 首次渲染显示灰色占位框（保持 4:3 比例）
- 解码完成后触发 `TextCanvas.onImageDecoded` 回调
- Widget 自动重新分页并刷新（`_engine.repaginate()`）

### 10.3 图片布局规则

- 图片独占一个段落（前后自动换行）
- 固定高度 + 保持原始宽高比
- 水平居中显示
- 如果宽度超出文本区域，按宽度缩放

---

## 11. 注意事项

1. **TextReaderWidget 必须有明确的尺寸约束**（放在 `Expanded`、`SizedBox`、`Scaffold.body` 等容器中），引擎需要知道视口大小来分页。

2. **`updateTextConfig` 会自动重新分页**，无需手动刷新。内部会清除元素宽度缓存、重建页面控制器并恢复阅读位置。

3. **EPUB / Markdown 网络图片是异步解码的**。首次渲染时显示占位框，解码完成后自动重新分页并刷新显示。

4. **`plugin.release()` 必须在不再使用时调用**，释放文件缓存和内存。

5. **CJK 文本自动优化**：格式检测器会识别中文/日文/韩文内容，自动使用逐字符断行（`breakParagraphAtNewLine`），无需手动配置。

6. **避免在 `onPageChanged` 回调中直接修改 Widget 构造参数**（如 `textConfig`），可能导致不必要的重新分页。

7. **Markdown 本地图片路径**以 `.md` 文件所在目录为基准解析，支持 `./` 和 `../` 相对路径。

8. **TextModel 内置 LRU 缓存**（5 个章节），频繁跳章不会导致重复解析。`TextEngine.setTextConfig()` 时自动清除缓存。

9. **翻页动画的 Picture 缓存**在配置变更、翻页完成时自动刷新，正常使用无需手动管理。
