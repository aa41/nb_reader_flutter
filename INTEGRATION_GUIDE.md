# NBreader Flutter 阅读引擎 — 接入文档

## 1. 概述

NBreader 是一个纯 Dart/Flutter 实现的电子书阅读引擎，移植自 Android NBReader（Kotlin/C++）。支持 **TXT** 和 **EPUB** 格式，提供完整的排版、分页、翻页动画和阅读设置能力。

### 核心能力

- TXT 文件解析（自动编码检测、章节识别、CJK 文本优化）
- EPUB 文件解析（OPF/NCX/XHTML、内嵌图片）
- 文本排版引擎（分词、断行、分页、样式继承）
- 5 种翻页动画（无、滑动、覆盖、仿真、滚动）
- 阅读设置（字号、行距、字距、边距、夜间模式）
- 阅读进度保存/恢复（推荐使用 TextFixedPosition，跨配置变更仍准确）
- 文字标注（长按选择、复制、高亮/下划线/波浪下划线、写想法虚线、持久化 + 点击编辑）

### 依赖项

NBreader 可以按“能力模块”拆分接入，你可以只引入需要的依赖：

```yaml
dependencies:
  # 核心阅读引擎（TXT/EPUB/排版）
  archive: ^4.0.4      # EPUB (ZIP) 解压
  xml: ^6.5.0          # XHTML/OPF/NCX 解析
  path: ^1.9.1         # 路径处理
  collection: ^1.19.1  # 工具集合（按需）

  # 可选：标注/进度持久化（示例实现）
  shared_preferences: ^2.2.0

  # 可选：Markdown 支持
  markdown: ^7.2.2

  # 可选：打开链接
  url_launcher: ^6.2.0

  # 可选：文件选择（示例 UI）
  file_picker: ^8.0.0
  path_provider: ^2.1.0
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

提示：以下示例以“将 NBreader 作为一个 package 引入”的 import 写法（`package:nbreader/...`）为例；如果你是直接复制源码到项目里，请根据你的目录结构调整 import。

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

**构造参数（常用）：**

- `textModel`（required）：数据模型
- `textConfig`：文本配置（字号/颜色/边距等）
- `animType`：翻页动画类型，默认 `slide`
- `onPageChanged`：页面变化回调
- `onCodeBlockTap` / `onImageTap` / `onLinkTap`：代码块/图片/链接点击回调（可选）
- `headerText` / `footerLeftText` / `footerRightText`：页眉/页脚（绘制在 margin 区域）
- `selectionMode`：是否处于选择态（true 时禁用翻页拖拽手势，便于实现长按选中/拖拽手柄）
- `safePaddingTop`：顶部安全区（用于避开刘海/状态栏区域）
- `onShowNoteBottomSheet`：自定义“写想法/编辑想法”BottomSheet（可选，详见第 10 章）

提示：完整参数请直接参考 `lib/widget/text_reader_widget.dart`。

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

// 标注（持久化标注会进入页面 Picture 缓存）
reader.setAnnotations(annotations);

// 选择态（动态 overlay，不进入 Picture 缓存）
reader.setSelectionRange(start, end);
reader.clearSelectionRange();

// 主动使页面 Picture 缓存失效并重绘（例如你直接改了引擎内部状态）
reader.invalidatePageCache();

// 写想法/编辑想法 BottomSheet（返回 null 表示取消）
final noteText = await reader.showNoteBottomSheet(
  note: noteAnnotation,
  selectedText: selectedText,
  isEdit: true,
);
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
  /// 打开书籍（异步读取文件）
  Future<void> openBook(String bookPath);

  /// 获取检测到的编码
  String getEncoding();

  /// 获取语言
  String getLanguage();

  /// 获取章节列表
  List<TextChapter> getChapters();

  /// 获取章节内容（输出 TextTag 列表）
  TextContent? getChapterContent(TextChapter chapter);

  /// 获取章节纯文本（用于全文搜索/预索引）
  /// 实现应与内容解析保持一致的空白折叠与段落换行策略，
  /// 以便后续根据字符偏移精确映射到 TextFixedPosition。
  String? getChapterPlainText(TextChapter chapter);

  /// 获取图片数据解析器（用于 EPUB 等格式内嵌图片的加载）
  ImageDataResolver? get imageDataResolver => null;

  /// 释放资源
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

- **左右滑动** → 翻页（跟手动画）

点击（上一页/下一页/呼出菜单）、长按选中、拖拽选择手柄等交互，建议由你的业务层在外部用 `Stack + GestureDetector` 实现（参考示例：`lib/ui/read/read_page.dart`）。

示例：左右点击翻页 + 中间点击呼出菜单

```dart
Stack(
  children: [
    Positioned.fill(
      child: TextReaderWidget(
        key: _readerKey,
        textModel: model,
      ),
    ),
    Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapUp: (d) {
          final reader = _readerKey.currentState;
          if (reader == null) return;

          final w = MediaQuery.of(context).size.width;
          final x = d.localPosition.dx;
          if (x < w / 3) {
            reader.turnPageAnimated(PageType.previous);
          } else if (x > w * 2 / 3) {
            reader.turnPageAnimated(PageType.next);
          } else {
            // open menu
          }
        },
      ),
    ),
  ],
)
```

当你进入“文本选择态”（长按选中 + 拖拽手柄）时，把 `selectionMode: true` 传给 `TextReaderWidget`，可自动禁用翻页拖拽手势，避免冲突。

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
│   ├── annotation/            # 文字标注（高亮/想法）数据结构
│   │   └── text_annotation.dart
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
├── data/                      # 数据持久化（可替换）
│   ├── book_repository.dart        # 阅读进度/书架等示例持久化
│   └── annotation_repository.dart  # 标注示例持久化
└── ui/                        # 示例 UI（可替换）
    ├── read/read_page.dart
    ├── read/read_menu.dart
    ├── read/annotation_widgets.dart
    └── bookshelf/bookshelf_page.dart
```

**接入时需要的最小文件集：** `parser/`、`text/`、`widget/` 三个目录。

- 如果你需要“文字标注持久化”，额外引入 `data/annotation_repository.dart`（或实现你自己的存储层）。
- 标注交互/UI 的参考实现：`ui/read/read_page.dart` + `ui/read/annotation_widgets.dart`。

`core/`、`data/`、`ui/` 是示例业务层，可按需替换。

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
  String? getChapterPlainText(TextChapter chapter) {
    // 返回章节纯文本（用于全文搜索/预索引）
    // 简单实现：复用 TextContent.toPlainText()
    return getChapterContent(chapter)?.toPlainText();
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

---

## 10. 文字标注（高亮/下划线/写想法）接入

本章描述如何在你的项目中接入“长按选中 + 工具条 + 高亮/下划线/波浪线 + 写想法（虚线）+ 持久化”。

### 10.1 数据结构与范围约定

标注数据结构位于：`lib/text/annotation/text_annotation.dart`

- `TextAnnotationKind`
  - `highlight`：高亮/划线
  - `note`：写想法（渲染为虚线下划线）
- `TextAnnotationStyleType`
  - `background` / `underline` / `wavyUnderline` / `dashedUnderline`
- `TextAnnotation`
  - `start` / `end`：使用 `TextFixedPosition` 定位
  - `noteText`：仅 `kind=note` 时有值

范围约定：

- 使用右开区间 `[start, end)`（end 为“右边界”，不包含）
- 永远保证 `start <= end`（库内部会做 normalize，但建议你在业务层也遵守）

### 10.2 渲染：持久标注 vs 选择态

- 持久标注：
  - 通过 `reader.setAnnotations(annotations)` 设置
  - 会进入页面 Picture 缓存，因此在翻页动画中也可见
- 选择态（长按选中）：
  - 通过 `reader.setSelectionRange(start, end)` / `reader.clearSelectionRange()`
  - 仅 overlay 绘制，不会污染 Picture 缓存
  - 进入选择态时建议设置 `selectionMode: true` 来禁用翻页拖拽

### 10.3 复制选中文本（保留空格与换行）

```dart
final reader = _readerKey.currentState!;
final text = reader.engine.extractText(start, end);
await Clipboard.setData(ClipboardData(text: text));
```

`extractText` 会尽量保持原始排版的空格/换行（章节间也会插入换行）。

### 10.4 命中检测与手柄定位

- 点击/长按命中到文字位置：

```dart
final pos = reader.engine.findTextPosition(dx, dy); // preferCharLevel=true 默认字符级
```

- 命中元素区域（可用于排除图片/代码块）：

```dart
final area = reader.engine.findHitArea(dx, dy);
```

- 选择手柄定位（把 TextFixedPosition 转成当前页坐标）：

```dart
final offset = reader.engine.getOffsetForTextPosition(pos);
```

### 10.5 自定义“写想法/编辑想法”BottomSheet

如果你需要在其它项目里复用自己的 UI，可以直接使用 `TextReaderWidget` 的回调：

- 构造参数：`onShowNoteBottomSheet`
- 回调定义见：`lib/widget/text_reader_widget.dart`

关键点：

- `isEdit=true` 表示编辑已有想法；`isEdit=false` 表示新建“写想法”
- `onCancel()` / `onConfirm(text)` 由外部 UI 在合适时机调用

示例：

```dart
TextReaderWidget(
  textModel: model,
  onShowNoteBottomSheet: (ctx, note, selectedText, isEdit, onCancel, onConfirm) {
    showModalBottomSheet(
      context: ctx,
      builder: (_) => MyNoteSheet(
        isEdit: isEdit,
        selectedText: selectedText,
        initialText: note.noteText ?? '',
        onCancel: () {
          Navigator.pop(ctx);
          onCancel();
        },
        onConfirm: (text) {
          Navigator.pop(ctx);
          onConfirm(text);
        },
      ),
    );
  },
)
```

### 10.6 标注持久化（示例实现，可替换）

示例的 SharedPreferences 存储在：`lib/data/annotation_repository.dart`

- `loadAnnotations(bookId)` / `saveAnnotations(bookId, annotations)`
- 存储格式为 JSON（你也可以替换为数据库/文件/云同步）

### 10.7 参考实现（可直接复制改造）

- 完整交互实现：`lib/ui/read/read_page.dart`
  - 长按选中、拖拽手柄
  - 角落热区自动翻页
  - 工具条 + 样式面板 + 颜色选择
  - 点击已有标注进入编辑、想法先展示再编辑
- UI 组件：`lib/ui/read/annotation_widgets.dart`
  - 工具条、样式面板、颜色点、选择手柄组件
