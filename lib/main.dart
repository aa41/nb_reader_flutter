import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';

// Phase 1: 数据结构验证
import 'core/book_type.dart';
import 'core/book_entity.dart';
import 'text/tag/text_tag.dart';
import 'text/tag/text_tag_type.dart';
import 'text/element/text_element.dart';
import 'text/element/text_word_element.dart';
import 'text/element/text_control_element.dart';
import 'text/element/text_fixed_hspace_element.dart';
import 'text/entity/text_chapter.dart';
import 'text/entity/text_content.dart';
import 'text/entity/text_paragraph.dart';
import 'text/entity/text_position.dart';
import 'text/entity/text_metrics.dart';
import 'text/style/tree_text_style.dart';
import 'text/config/text_config.dart';
import 'text/util/line_breaker.dart';
import 'widget/page_enum.dart';

// Phase 2: TXT 解析
import 'parser/encoding/encoding_detector.dart';
import 'parser/txt/plain_text_format.dart';
import 'parser/txt/txt_chapter_detector.dart';
import 'parser/txt/txt_reader.dart';
import 'parser/txt/txt_plugin.dart';

// Phase 3: EPUB 解析
import 'parser/epub/container_reader.dart';
import 'parser/epub/opf_reader.dart';
import 'parser/epub/ncx_reader.dart';
import 'parser/epub/xhtml_content_reader.dart';
import 'parser/epub/epub_plugin.dart';

// Phase 4: 排版引擎
import 'parser/format_plugin.dart';
import 'text/engine/text_model.dart';
import 'text/engine/cursor/text_word_cursor.dart';
import 'text/engine/text_engine.dart';

// Phase 5: 文本渲染
import 'text/engine/text_page_controller.dart';
import 'widget/text_reader_widget.dart';

// Phase 6: 翻页动画

// Phase 7: UI
import 'ui/bookshelf/bookshelf_page.dart';

void main() {
  // === 完整应用 ===
  runApp(const NBReaderApp());

  // === 测试入口 ===
  // runApp(const Phase1TestApp());  // 数据结构
  // runApp(const Phase2TestApp());  // TXT 解析
  // runApp(const Phase3TestApp());  // EPUB 解析
  // runApp(const Phase4TestApp());  // 排版引擎
  // runApp(const Phase5TestApp());  // 文本渲染
  // runApp(const Phase6TestApp());  // 翻页动画
}

/// 完整应用入口
class NBReaderApp extends StatelessWidget {
  const NBReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NBReader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8B6914)),
        useMaterial3: true,
      ),
      home: const BookshelfPage(),
    );
  }
}

class Phase1TestApp extends StatelessWidget {
  const Phase1TestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NBReader - Phase 1 Test',
      theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
      home: const Phase1TestPage(),
    );
  }
}

class Phase1TestPage extends StatefulWidget {
  const Phase1TestPage({super.key});

  @override
  State<Phase1TestPage> createState() => _Phase1TestPageState();
}

class _Phase1TestPageState extends State<Phase1TestPage> {
  final List<String> _results = [];

  @override
  void initState() {
    super.initState();
    _runTests();
  }

  void _runTests() {
    _results.clear();

    // 1. BookType 测试
    _test('BookType', () {
      assert(BookType.fromExtension('.txt') == BookType.txt);
      assert(BookType.fromExtension('.epub') == BookType.epub);
      assert(BookType.fromExtension('.pdf') == null);
      return 'BookType.fromExtension ✓';
    });

    // 2. BookEntity 测试
    _test('BookEntity', () {
      final book = BookEntity(
        id: '1', title: '测试书籍', url: '/path/test.txt', type: BookType.txt,
      );
      assert(book.title == '测试书籍');
      final updated = book.copyWith(lastChapterIndex: 5);
      assert(updated.lastChapterIndex == 5);
      assert(updated.title == '测试书籍');
      return '$book ✓';
    });

    // 3. TextTag 系列测试
    _test('TextTag', () {
      final contentTag = TextContentTag('Hello World 你好世界');
      final controlTag = TextControlTag(TextControlType.h1, true);
      final paragraphTag = TextParagraphTag(TextParagraphType.textParagraph);
      final styleCloseTag = TextStyleCloseTag.instance;
      final imageTag = TextImageTag('img001', isCover: true);
      assert(contentTag.content == 'Hello World 你好世界');
      assert(controlTag.isStart == true);
      assert(paragraphTag.type == 0);
      return '$contentTag | $controlTag | $paragraphTag | $styleCloseTag | $imageTag ✓';
    });

    // 4. TextElement 系列测试
    _test('TextElement', () {
      final word = TextWordElement.fromString('Hello');
      assert(word.getString() == 'Hello');
      assert(word.length == 5);
      final ctrl = TextControlElement(TextControlType.strong, true);
      assert(ctrl.isStart == true);
      final hspace = TextFixedHSpaceElement.getElement(10);
      assert(hspace.length == 10);
      // 单例验证
      assert(identical(TextElement.hSpace, TextElement.hSpace));
      assert(identical(TextFixedHSpaceElement.getElement(10), hspace));
      return '$word | $ctrl | $hspace ✓';
    });

    // 5. TextChapter, TextParagraph 测试
    _test('TextChapter/Paragraph', () {
      final chapter = TextChapter(
          url: '/book.txt', title: '第一章', startIndex: 0, endIndex: 1024);
      final para = TextParagraph(
        type: TextParagraphType.textParagraph, indexFromChapter: 0,
        startOffset: 0, endOffset: 5,
      );
      return '$chapter | $para ✓';
    });

    // 6. TextContent 测试
    _test('TextContent', () {
      final content = TextContent(tags: [
        TextContentTag('第一段文本'),
        TextParagraphTag(TextParagraphType.textParagraph),
        TextContentTag('第二段文本'),
        TextParagraphTag(TextParagraphType.textParagraph),
      ]);
      assert(content.tags.length == 4);
      return '$content ✓';
    });

    // 7. TextPosition 测试
    _test('TextPosition', () {
      final pos1 = TextFixedPosition(
          chapterIndex: 0, paragraphIndex: 0, elementIndex: 0, charIndex: 0);
      final pos2 = TextFixedPosition(
          chapterIndex: 0, paragraphIndex: 1, elementIndex: 0, charIndex: 0);
      assert(pos1 < pos2);
      assert(pos2 > pos1);
      return '$pos1 < $pos2 ✓';
    });

    // 8. TreeTextStyle 测试
    _test('TreeTextStyle', () {
      final base = TreeTextStyle(fontSize: 16);
      final child = base.createChild(bold: true, fontSize: 24);
      assert(child.parent == base);
      assert(child.getFontSize() == 24);
      assert(child.isBold() == true);
      assert(base.isBold() == false);
      return '$base -> $child ✓';
    });

    // 9. TextConfig 测试
    _test('TextConfig', () {
      final config = TextConfig(marginTop: 30, marginLeft: 25);
      assert(config.getMarginTop() == 30);
      assert(config.getMarginLeft() == 25);
      final baseStyle = config.getBaseTextStyle();
      final h1Style = config.getControlDecoratedStyle(
          baseStyle, TextControlType.h1);
      assert(h1Style.getFontSize() == 28);
      assert(h1Style.isBold() == true);
      return 'TextConfig margins=${config.getMarginTop()},${config
          .getMarginLeft()} | h1=${h1Style.getFontSize()}px bold ✓';
    });

    // 10. LineBreaker 测试
    _test('LineBreaker', () {
      final text = '你好世界Hello';
      final data = text.codeUnits;
      final result = List<int>.filled(data.length, 0);
      LineBreaker.setLineBreak(data, 0, data.length, 'zh', result);
      // 中文字符之间应该允许断行
      assert(result[0] == LineBreaker.allowBreak); // 你|好
      assert(result[1] == LineBreaker.allowBreak); // 好|世
      assert(result[2] == LineBreaker.allowBreak); // 世|界
      assert(result[3] == LineBreaker.allowBreak); // 界|H (CJK->Latin)
      // Latin 单词内部不断行
      assert(result[4] == LineBreaker.nobreak); // H|e
      return 'LineBreaker: $result ✓';
    });

    // 11. PageEnum 测试
    _test('PageEnum', () {
      assert(PageType.current.getNext() == PageType.next);
      assert(PageType.current.getPrevious() == PageType.previous);
      assert(PageAnimType.values.length == 5);
      return 'PageType & PageAnimType ✓';
    });

    // 12. TextMetrics 测试
    _test('TextMetrics', () {
      final metrics = TextMetrics(
          dpi: 320, screenWidth: 1080, screenHeight: 1920, baseFontSize: 16);
      return '$metrics ✓';
    });

    // 打印结果到控制台
    debugPrint('\n===== Phase 1 测试结果 =====');
    for (final r in _results) {
      debugPrint(r);
    }
    debugPrint('============================\n');
    setState(() {});
  }

  void _test(String name, String Function() testFn) {
    try {
      final result = testFn();
      _results.add('✅ $name: $result');
    } catch (e) {
      _results.add('❌ $name: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Phase 1: 数据结构验证'),
        backgroundColor: Theme
            .of(context)
            .colorScheme
            .inversePrimary,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _results.length,
        itemBuilder: (_, i) =>
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(_results[i], style: const TextStyle(fontSize: 13)),
            ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => setState(() => _runTests()),
        child: const Icon(Icons.refresh),
      ),
    );
  }
}

// ==================== Phase 2: TXT 解析测试 ====================

/// 测试用 TXT 内容
const _phase2TestContent = '''这是一本测试书籍的序言部分。这里是正式内容开始之前的一些说明文字。
本书由多位作者共同编写，涉及多个主题的讨论与分析。
感谢所有参与本书编写的人员，是你们的努力使本书得以完成。
欢迎各位读者阅读本书，希望能给你带来一些启发和帮助。

第一章 初遇
人生若只如初见，何事秋风悲画扇。
等闲变却故人心，却道故人心易变。

骊山语罢清宵半，泪雨霖铃终不怨。
何如薄幸锦衣郎，比翼连枝当日愿。

第二章 重逢
去年今日此门中，人面桃花相映红。
人面不知何处去，桃花依旧笑春风。

第三章 离别
多情自古伤离别，更那堪冷落清秋节。
今宵酒醒何处，杨柳岸晓风残月。
此去经年，应是良辰好景虚设。
便纵有千种风情，更与何人说。
''';

class Phase2TestApp extends StatelessWidget {
  const Phase2TestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NBReader - Phase 2 Test',
      theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
      home: const Phase2TestPage(),
    );
  }
}

class Phase2TestPage extends StatefulWidget {
  const Phase2TestPage({super.key});

  @override
  State<Phase2TestPage> createState() => _Phase2TestPageState();
}

class _Phase2TestPageState extends State<Phase2TestPage> {
  final List<String> _results = [];
  bool _isRunning = true;

  @override
  void initState() {
    super.initState();
    _runTests();
  }

  Future<void> _runTests() async {
    _results.clear();

    // 1. BOM 检测
    await _test('BOM Detection', () async {
      final utf8Bom = Uint8List.fromList([0xEF, 0xBB, 0xBF, 0x48, 0x69]);
      final utf16leBom = Uint8List.fromList([0xFF, 0xFE, 0x48, 0x00]);
      final noBom = Uint8List.fromList([0x48, 0x65, 0x6C, 0x6C, 0x6F]);
      assert(EncodingDetector.detectBOM(utf8Bom) == 'utf-8');
      assert(EncodingDetector.detectBOM(utf16leBom) == 'utf-16le');
      assert(EncodingDetector.detectBOM(noBom) == null);
      return 'UTF-8 BOM ✓ | UTF-16LE BOM ✓ | No BOM ✓';
    });

    // 2. 编码检测
    await _test('Encoding Detection', () async {
      final utf8Data = Uint8List.fromList(utf8.encode('你好世界'));
      final encoding = EncodingDetector.detect(utf8Data);
      assert(encoding == 'utf-8');
      final decoded = EncodingDetector.decode(utf8Data, encoding);
      assert(decoded == '你好世界');
      return 'detect=$encoding, decode="$decoded" ✓';
    });

    // 3. PlainTextDetector
    await _test('PlainTextDetector', () async {
      final format = PlainTextDetector.detect(_phase2TestContent);
      assert(format.breakType != 0);
      assert(format.ignoredIndent >= 1);
      return '$format ✓';
    });

    // 4. TxtChapterDetector
    await _test('TxtChapterDetector', () async {
      final chapters = TxtChapterDetector.detect(
          _phase2TestContent, '/test.txt');
      assert(chapters.length >= 3);
      final titles = chapters.map((c) => c.title).toList();
      assert(titles.any((t) => t.contains('第一章')));
      assert(titles.any((t) => t.contains('第二章')));
      assert(titles.any((t) => t.contains('第三章')));
      return '${chapters.length}章: ${titles.join(", ")} ✓';
    });

    // 5. TxtReader
    await _test('TxtReader', () async {
      final format = PlainTextFormat(
        breakType: PlainTextFormat.breakParagraphAtEmptyLine |
        PlainTextFormat.breakParagraphAtNewLine,
      );
      final content = TxtReader.parse('测试第一行\n\n测试第二行', format);
      final textTags = content.tags.whereType<TextContentTag>().toList();
      final paraTags = content.tags.whereType<TextParagraphTag>().toList();
      assert(textTags.length == 2);
      assert(textTags[0].content.contains('测试第一行'));
      return 'tags=${content.tags.length}, text=${textTags
          .length}, para=${paraTags.length} ✓';
    });

    // 6. TxtReader 标题测试
    await _test('TxtReader Title', () async {
      final format = PlainTextFormat(
        breakType: PlainTextFormat.breakParagraphAtNewLine,
      );
      final content = TxtReader.parse(
          '第一章 测试\n正文内容', format, hasTitleLine: true);
      final controlTags = content.tags.whereType<TextControlTag>().toList();
      final titleTags = controlTags.where((t) =>
      t.type == TextControlType.title).toList();
      assert(titleTags.isNotEmpty);
      return 'title tags=${titleTags.length}, total controls=${controlTags
          .length} ✓';
    });

    // 7. TxtPlugin 完整流程
    await _test('TxtPlugin Pipeline', () async {
      final dir = Directory.systemTemp;
      final testFile = File('${dir.path}/nbreader_test_${DateTime
          .now()
          .millisecondsSinceEpoch}.txt');
      try {
        await testFile.writeAsString(_phase2TestContent, encoding: utf8);

        final plugin = TxtPlugin();
        await plugin.openBook(testFile.path);

        assert(plugin.getEncoding() == 'utf-8');

        final chapters = plugin.getChapters();
        assert(chapters.length >= 3);

        // 读取第一章内容
        final firstContent = plugin.getChapterContent(chapters[0]);
        assert(firstContent != null);
        assert(firstContent!.tags.isNotEmpty);

        // 读取末章内容
        final lastContent = plugin.getChapterContent(chapters.last);
        assert(lastContent != null);

        final buf = StringBuffer();
        buf.write('enc=${plugin.getEncoding()}, ch=${chapters.length}');
        for (final c in chapters) {
          buf.write('\n   「${c.title}」(${c.endIndex - c.startIndex}字)');
        }
        buf.write(
            '\n   首章tags=${firstContent!.tags.length}, 末章tags=${lastContent!
                .tags.length} ✓');

        plugin.release();
        return buf.toString();
      } finally {
        if (await testFile.exists()) await testFile.delete();
      }
    });

    // 8. 章节内容详情验证
    await _test('Chapter Content Detail', () async {
      final dir = Directory.systemTemp;
      final testFile = File('${dir.path}/nbreader_test2_${DateTime
          .now()
          .millisecondsSinceEpoch}.txt');
      try {
        await testFile.writeAsString(_phase2TestContent, encoding: utf8);

        final plugin = TxtPlugin();
        await plugin.openBook(testFile.path);
        final chapters = plugin.getChapters();

        // 查找「第一章」
        final ch1 = chapters.firstWhere((c) => c.title.contains('第一章'));
        final content = plugin.getChapterContent(ch1)!;

        // 验证标签结构
        final textTags = content.tags.whereType<TextContentTag>().toList();
        final paraTags = content.tags.whereType<TextParagraphTag>().toList();

        assert(textTags.isNotEmpty);
        assert(paraTags.length >= 2); // 至少有段落 + endOfSection

        // 第一个文本应包含章节标题
        assert(textTags.first.content.contains('第一章'));

        plugin.release();
        final preview = textTags.first.content;
        final previewText = preview.length > 10 ? '${preview.substring(
            0, 10)}...' : preview;
        return 'text=${textTags.length}, para=${paraTags
            .length}, first="$previewText" \u2713';
      } finally {
        if (await testFile.exists()) await testFile.delete();
      }
    });

    // 打印结果到控制台
    debugPrint('\n===== Phase 2 测试结果 =====');
    for (final r in _results) {
      debugPrint(r);
    }
    debugPrint('============================\n');
    setState(() => _isRunning = false);
  }

  Future<void> _test(String name, Future<String> Function() testFn) async {
    try {
      final result = await testFn();
      _results.add('✅ $name: $result');
    } catch (e) {
      _results.add('❌ $name: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Phase 2: TXT 解析验证'),
        backgroundColor: Theme
            .of(context)
            .colorScheme
            .inversePrimary,
      ),
      body: _isRunning
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _results.length,
        itemBuilder: (_, i) =>
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(_results[i], style: const TextStyle(fontSize: 13)),
            ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() => _isRunning = true);
          _runTests();
        },
        child: const Icon(Icons.refresh),
      ),
    );
  }
}

// ==================== Phase 3: EPUB 解析测试 ====================

/// 在内存中构建一个最小的合法 EPUB 文件
Uint8List _buildTestEpub() {
  final archive = Archive();

  void addFile(String name, String content) {
    final data = Uint8List.fromList(utf8.encode(content));
    archive.addFile(ArchiveFile(name, data.length, data));
  }

  // 1. mimetype（EPUB 规范要求为第一个文件，无压缩）
  addFile('mimetype', 'application/epub+zip');

  // 2. META-INF/container.xml
  addFile('META-INF/container.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
''');

  // 3. OEBPS/content.opf
  addFile('OEBPS/content.opf', '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="BookId">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>测试书籍</dc:title>
    <dc:creator>测试作者</dc:creator>
    <dc:language>zh</dc:language>
    <dc:identifier id="BookId">test-epub-001</dc:identifier>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch3" href="chapter3.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="ch1"/>
    <itemref idref="ch2"/>
    <itemref idref="ch3"/>
  </spine>
</package>
''');

  // 4. OEBPS/toc.ncx
  addFile('OEBPS/toc.ncx', '''
<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head>
    <meta name="dtb:uid" content="test-epub-001"/>
  </head>
  <docTitle><text>测试书籍</text></docTitle>
  <navMap>
    <navPoint id="np1" playOrder="1">
      <navLabel><text>第一章 初遇</text></navLabel>
      <content src="chapter1.xhtml"/>
    </navPoint>
    <navPoint id="np2" playOrder="2">
      <navLabel><text>第二章 重逢</text></navLabel>
      <content src="chapter2.xhtml"/>
    </navPoint>
    <navPoint id="np3" playOrder="3">
      <navLabel><text>第三章 离别</text></navLabel>
      <content src="chapter3.xhtml"/>
    </navPoint>
  </navMap>
</ncx>
''');

  // 5. 章节 XHTML 文件
  addFile('OEBPS/chapter1.xhtml', '''
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>第一章</title></head>
<body>
  <h1>第一章 初遇</h1>
  <p>人生若只如初见，何事秋风悲画扇。</p>
  <p>等闲变却故人心，却道故人心易变。</p>
  <p>这段文字包含<strong>加粗</strong>和<em>斜体</em>标记。</p>
</body>
</html>
''');

  addFile('OEBPS/chapter2.xhtml', '''
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>第二章</title></head>
<body>
  <h2>第二章 重逢</h2>
  <p>去年今日此门中，人面桃花相映红。</p>
  <p>人面不知何处去，桃花依旧笑春风。</p>
  <ul>
    <li>列表项一</li>
    <li>列表项二</li>
  </ul>
</body>
</html>
''');

  addFile('OEBPS/chapter3.xhtml', '''
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>第三章</title></head>
<body>
  <h3>第三章 离别</h3>
  <p>多情自古伤离别，更那堪冷落清秋节。</p>
  <div>今宵酒醒何处，杨柳岸晓风残月。</div>
  <p>此去经年，应是良辰好景虚设。</p>
  <p>便纵有<code>千种风情</code>，更与何人说。</p>
</body>
</html>
''');

  return Uint8List.fromList(ZipEncoder().encode(archive));
}

class Phase3TestApp extends StatelessWidget {
  const Phase3TestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NBReader - Phase 3 Test',
      theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
      home: const Phase3TestPage(),
    );
  }
}

class Phase3TestPage extends StatefulWidget {
  const Phase3TestPage({super.key});

  @override
  State<Phase3TestPage> createState() => _Phase3TestPageState();
}

class _Phase3TestPageState extends State<Phase3TestPage> {
  final List<String> _results = [];
  bool _isRunning = true;

  @override
  void initState() {
    super.initState();
    _runTests();
  }

  Future<void> _runTests() async {
    _results.clear();

    // 1. ContainerReader 单元测试
    await _test('ContainerReader', () async {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
''';
      final path = ContainerReader.readOpfPath(xml);
      assert(path == 'OEBPS/content.opf');
      return 'OPF path=$path ✓';
    });

    // 2. OpfReader 单元测试
    await _test('OpfReader', () async {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="BookId">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>测试书籍</dc:title>
    <dc:creator>测试作者</dc:creator>
    <dc:language>zh</dc:language>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="ch1"/>
    <itemref idref="ch2"/>
  </spine>
</package>
''';
      final data = OpfReader.read(xml, 'OEBPS/content.opf');
      assert(data.opfDirPath == 'OEBPS/');
      assert(data.ncxFileName == 'toc.ncx');
      assert(data.spineHrefs.length == 2);
      assert(data.metadata['title'] == '测试书籍');
      return 'dir=${data.opfDirPath}, ncx=${data.ncxFileName}, spine=${data
          .spineHrefs.length}, title=${data.metadata['title']} ✓';
    });

    // 3. NcxReader 单元测试
    await _test('NcxReader', () async {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <navMap>
    <navPoint id="np1" playOrder="1">
      <navLabel><text>第一章</text></navLabel>
      <content src="ch1.xhtml"/>
    </navPoint>
    <navPoint id="np2" playOrder="2">
      <navLabel><text>第二章</text></navLabel>
      <content src="ch2.xhtml"/>
    </navPoint>
  </navMap>
</ncx>
''';
      final points = NcxReader.read(xml);
      assert(points.length == 2);
      assert(points[0].text == '第一章');
      assert(points[1].contentHref == 'ch2.xhtml');
      return '${points.length} navPoints: ${points.map((p) => p.text).join(
          ", ")} ✓';
    });

    // 4. XhtmlContentReader 单元测试
    await _test('XhtmlContentReader', () async {
      const xhtml = '''
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Test</title></head>
<body>
  <h1>标题一</h1>
  <p>普通段落文本。</p>
  <p>包含<strong>加粗</strong>和<em>斜体</em>的文本。</p>
</body>
</html>
''';
      final content = XhtmlContentReader.parse(xhtml);
      final textTags = content.tags.whereType<TextContentTag>().toList();
      final controlTags = content.tags.whereType<TextControlTag>().toList();
      final paraTags = content.tags.whereType<TextParagraphTag>().toList();

      assert(textTags.isNotEmpty);
      assert(controlTags.isNotEmpty);
      assert(paraTags.isNotEmpty);

      // 验证 h1 标签
      final h1Tags = controlTags.where((t) => t.type == TextControlType.h1)
          .toList();
      assert(h1Tags.length == 2); // 开始 + 结束
      assert(h1Tags[0].isStart == true);
      assert(h1Tags[1].isStart == false);

      // 验证 strong 标签
      final strongTags = controlTags.where((t) =>
      t.type == TextControlType.strong).toList();
      assert(strongTags.length == 2);

      return 'text=${textTags.length}, ctrl=${controlTags
          .length}, para=${paraTags.length}, h1=${h1Tags
          .length}, strong=${strongTags.length} ✓';
    });

    // 5. XhtmlContentReader 列表和代码测试
    await _test('XhtmlContentReader Lists & Code', () async {
      const xhtml = '''
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Test</title></head>
<body>
  <ul>
    <li>项目一</li>
    <li>项目二</li>
  </ul>
  <p>包含<code>代码片段</code>的段落。</p>
</body>
</html>
''';
      final content = XhtmlContentReader.parse(xhtml);
      final textTags = content.tags.whereType<TextContentTag>().toList();

      // 应包含列表项的 bullet 符号
      final bulletTags = textTags.where((t) => t.content.contains('•'))
          .toList();
      assert(bulletTags.length == 2);

      // 验证 code 标签
      final controlTags = content.tags.whereType<TextControlTag>().toList();
      final codeTags = controlTags.where((t) => t.type == TextControlType.code)
          .toList();
      assert(codeTags.length == 2);

      return 'bullets=${bulletTags.length}, code=${codeTags.length} ✓';
    });

    // 6. EpubPlugin 完整流程
    await _test('EpubPlugin Pipeline', () async {
      final epubBytes = _buildTestEpub();
      final dir = Directory.systemTemp;
      final testFile = File('${dir.path}/nbreader_test_${DateTime
          .now()
          .millisecondsSinceEpoch}.epub');

      try {
        await testFile.writeAsBytes(epubBytes);

        final plugin = EpubPlugin();
        await plugin.openBook(testFile.path);

        // 验证元数据
        assert(plugin.getEncoding() == 'utf-8');
        assert(plugin.getLanguage() == 'zh');
        assert(plugin.title == '测试书籍');
        assert(plugin.author == '测试作者');

        // 验证章节列表
        final chapters = plugin.getChapters();
        assert(chapters.length == 3);
        assert(chapters[0].title.contains('第一章'));
        assert(chapters[1].title.contains('第二章'));
        assert(chapters[2].title.contains('第三章'));

        final buf = StringBuffer();
        buf.write(
            'title=${plugin.title}, lang=${plugin.getLanguage()}, ch=${chapters
                .length}');
        for (final c in chapters) {
          buf.write('\n   「${c.title}」→ ${c.url}');
        }

        plugin.release();
        return buf.toString();
      } finally {
        if (await testFile.exists()) await testFile.delete();
      }
    });

    // 7. EpubPlugin 章节内容读取
    await _test('EpubPlugin Chapter Content', () async {
      final epubBytes = _buildTestEpub();
      final dir = Directory.systemTemp;
      final testFile = File('${dir.path}/nbreader_test2_${DateTime
          .now()
          .millisecondsSinceEpoch}.epub');

      try {
        await testFile.writeAsBytes(epubBytes);

        final plugin = EpubPlugin();
        await plugin.openBook(testFile.path);
        final chapters = plugin.getChapters();

        // 读取第一章
        final ch1Content = plugin.getChapterContent(chapters[0]);
        assert(ch1Content != null);
        final ch1Text = ch1Content!.tags.whereType<TextContentTag>().toList();
        final ch1Ctrl = ch1Content.tags.whereType<TextControlTag>().toList();
        assert(ch1Text.isNotEmpty);
        // 应包含 h1, strong, em 控制标签
        assert(ch1Ctrl
            .where((t) => t.type == TextControlType.h1)
            .isNotEmpty);
        assert(ch1Ctrl
            .where((t) => t.type == TextControlType.strong)
            .isNotEmpty);
        assert(ch1Ctrl
            .where((t) => t.type == TextControlType.emphasis)
            .isNotEmpty);

        // 读取第二章
        final ch2Content = plugin.getChapterContent(chapters[1]);
        assert(ch2Content != null);
        final ch2Text = ch2Content!.tags.whereType<TextContentTag>().toList();
        // 第二章应包含 h2 和 li 列表项
        final ch2Ctrl = ch2Content.tags.whereType<TextControlTag>().toList();
        assert(ch2Ctrl
            .where((t) => t.type == TextControlType.h2)
            .isNotEmpty);
        final ch2Bullets = ch2Text.where((t) => t.content.contains('•'))
            .toList();
        assert(ch2Bullets.length == 2);

        // 读取第三章
        final ch3Content = plugin.getChapterContent(chapters[2]);
        assert(ch3Content != null);
        final ch3Ctrl = ch3Content!.tags.whereType<TextControlTag>().toList();
        assert(ch3Ctrl
            .where((t) => t.type == TextControlType.h3)
            .isNotEmpty);
        assert(ch3Ctrl
            .where((t) => t.type == TextControlType.code)
            .isNotEmpty);

        plugin.release();
        return 'ch1: text=${ch1Text.length}, ctrl=${ch1Ctrl
            .length} | ch2: bullets=${ch2Bullets.length} | ch3: has h3+code ✓';
      } finally {
        if (await testFile.exists()) await testFile.delete();
      }
    });

    // 8. XhtmlContentReader 降级处理
    await _test('XhtmlContentReader Fallback', () async {
      // 故意传入不合法的 HTML
      final content = XhtmlContentReader.parse('<bad>这是<broken>不合法的HTML');
      // 应该降级为纯文本
      final textTags = content.tags.whereType<TextContentTag>().toList();
      assert(textTags.isNotEmpty);
      // 最后应有 endOfSection
      final paraTags = content.tags.whereType<TextParagraphTag>().toList();
      final lastPara = paraTags.last;
      assert(lastPara.type == TextParagraphType.endOfSectionParagraph);
      return 'fallback text=${textTags.length}, endOfSection ✓';
    });

    // 打印结果到控制台
    debugPrint('\n===== Phase 3 测试结果 =====');
    for (final r in _results) {
      debugPrint(r);
    }
    debugPrint('============================\n');
    setState(() => _isRunning = false);
  }

  Future<void> _test(String name, Future<String> Function() testFn) async {
    try {
      final result = await testFn();
      _results.add('✅ $name: $result');
    } catch (e, st) {
      _results.add('❌ $name: $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Phase 3: EPUB 解析验证'),
        backgroundColor: Theme
            .of(context)
            .colorScheme
            .inversePrimary,
      ),
      body: _isRunning
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _results.length,
        itemBuilder: (_, i) =>
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(_results[i], style: const TextStyle(fontSize: 13)),
            ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() => _isRunning = true);
          _runTests();
        },
        child: const Icon(Icons.refresh),
      ),
    );
  }
}

// ==================== Phase 4: 排版引擎测试 ====================

/// 测试用 Mock FormatPlugin
class _MockFormatPlugin extends FormatPlugin {
  final List<TextChapter> _chapters;
  final Map<String, TextContent> _contents;

  _MockFormatPlugin(this._chapters, this._contents);

  /// 创建包含 2 章的测试插件
  factory _MockFormatPlugin.twoChapters() {
    final chapters = [
      const TextChapter(
          url: 'ch1', title: '第一章 测试', startIndex: 0, endIndex: 100),
      const TextChapter(
          url: 'ch2', title: '第二章 中文排版', startIndex: 100, endIndex: 200),
    ];

    // 第一章: 2 段纯文本
    final ch1Tags = <TextTag>[
      const TextContentTag('Hello World 你好世界'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag('This is a test paragraph with multiple words.'),
      const TextParagraphTag(TextParagraphType.textParagraph),
    ];

    // 第二章: 带控制标签的富文本 + 3 段
    final ch2Tags = <TextTag>[
      const TextControlTag(TextControlType.h1, true),
      const TextContentTag('章节标题'),
      const TextControlTag(TextControlType.h1, false),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextControlTag(TextControlType.strong, true),
      const TextContentTag('加粗文本'),
      const TextControlTag(TextControlType.strong, false),
      const TextContentTag('普通文本紧随其后'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '这是一段较长的中文内容用来测试CJK断行能力。每个中文字符之间都应该可以断行。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
    ];

    return _MockFormatPlugin(chapters, {
      'ch1': TextContent(tags: ch1Tags),
      'ch2': TextContent(tags: ch2Tags),
    });
  }

  @override
  Future<void> openBook(String bookPath) async {}

  @override
  String getEncoding() => 'utf-8';

  @override
  String getLanguage() => 'zh';

  @override
  List<TextChapter> getChapters() => _chapters;

  @override
  TextContent? getChapterContent(TextChapter chapter) => _contents[chapter.url];

  @override
  String? getChapterPlainText(TextChapter chapter) => null;

  @override
  void release() {}
}

class Phase4TestApp extends StatelessWidget {
  const Phase4TestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NBReader - Phase 4 Test',
      theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange)),
      home: const Phase4TestPage(),
    );
  }
}

class Phase4TestPage extends StatefulWidget {
  const Phase4TestPage({super.key});

  @override
  State<Phase4TestPage> createState() => _Phase4TestPageState();
}

class _Phase4TestPageState extends State<Phase4TestPage> {
  final List<String> _results = [];
  bool _isRunning = true;

  @override
  void initState() {
    super.initState();
    _runTests();
  }

  Future<void> _runTests() async {
    _results.clear();

    // 1. TextModel 基础
    await _test('TextModel 基础', () async {
      final plugin = _MockFormatPlugin.twoChapters();
      final model = TextModel(plugin);
      assert(model.getChapterCount() == 2);
      assert(model.getLanguage() == 'zh');
      final ch0 = model.getChapter(0);
      assert(ch0.title == '第一章 测试');
      final content = model.getChapterContent(0);
      assert(content != null);
      assert(content!.tags.length == 4);
      return 'chapters=${model.getChapterCount()}, ch0.tags=${content!.tags
          .length} ✓';
    });

    // 2. TextChapterCursor 段落提取
    await _test('TextChapterCursor 段落提取', () async {
      final plugin = _MockFormatPlugin.twoChapters();
      final model = TextModel(plugin);
      final cursor0 = model.getChapterCursor(0);
      // 第一章: 2 个 ParagraphTag → 2 段
      assert(cursor0.getParagraphCount() == 2);
      assert(cursor0.isFirstChapter());
      assert(!cursor0.isLastChapter());
      final cursor1 = model.getChapterCursor(1);
      // 第二章: 3 个 ParagraphTag → 3 段
      assert(cursor1.getParagraphCount() == 3);
      assert(cursor1.isLastChapter());
      // 上下章导航
      final next = cursor0.nextCursor();
      assert(next != null && next.chapterIndex == 1);
      final prev = cursor1.prevCursor();
      assert(prev != null && prev.chapterIndex == 0);
      return 'ch0: ${cursor0.getParagraphCount()} paras | ch1: ${cursor1
          .getParagraphCount()} paras | nav ✓';
    });

    // 3. TextModel LRU 缓存
    await _test('TextModel LRU 缓存', () async {
      final plugin = _MockFormatPlugin.twoChapters();
      final model = TextModel(plugin);
      final c1 = model.getChapterCursor(0);
      final c2 = model.getChapterCursor(0);
      // 缓存应返回同一实例
      assert(identical(c1, c2));
      // 不同章节应返回不同实例
      final c3 = model.getChapterCursor(1);
      assert(!identical(c1, c3));
      return 'same chapter → identical=${identical(
          c1, c2)}, diff chapter → identical=${identical(c1, c3)} ✓';
    });

    // 4. TextParagraphCursor 解码与CJK断行
    await _test('ParagraphCursor CJK 断行', () async {
      final plugin = _MockFormatPlugin.twoChapters();
      final model = TextModel(plugin);
      final chCursor = model.getChapterCursor(0);
      final paraCursor = chCursor.getParagraphCursor(0);
      // 'Hello World 你好世界' → 应产生: 'Hello', hSpace, 'World', hSpace, 你, 好, 世, 界
      final elemCount = paraCursor.getElementCount();
      assert(elemCount > 0);
      // 收集所有 TextWordElement
      final words = <String>[];
      for (int i = 0; i < elemCount; i++) {
        final elem = paraCursor.getElement(i);
        if (elem is TextWordElement) {
          words.add(elem.getString());
        }
      }
      // 应包含 Hello, World 以及各个中文字符
      assert(words.contains('Hello'));
      assert(words.contains('World'));
      // 中文字符应被逐字拆分
      assert(words.contains('你'));
      assert(words.contains('好'));
      assert(words.contains('世'));
      assert(words.contains('界'));
      return 'elements=$elemCount, words=$words ✓';
    });

    // 5. TextParagraphCursor 控制标签解码
    await _test('ParagraphCursor 控制标签', () async {
      final plugin = _MockFormatPlugin.twoChapters();
      final model = TextModel(plugin);
      final chCursor = model.getChapterCursor(1);
      // 第二章第一段: [ControlStart(h1), '章节标题', ControlEnd(h1)]
      final paraCursor = chCursor.getParagraphCursor(0);
      final elemCount = paraCursor.getElementCount();
      assert(elemCount >= 3); // 至少包含 控制开始+文字+控制结束
      // 首个元素应该是 TextControlElement(h1, start)
      final first = paraCursor.getElement(0);
      assert(first is TextControlElement);
      final firstCtrl = first as TextControlElement;
      assert(firstCtrl.type == TextControlType.h1);
      assert(firstCtrl.isStart == true);
      return 'ch1.para0: elemCount=$elemCount, first=$first ✓';
    });

    // 6. TextWordCursor 导航
    await _test('TextWordCursor 导航', () async {
      final plugin = _MockFormatPlugin.twoChapters();
      final model = TextModel(plugin);
      final chCursor = model.getChapterCursor(0);
      final paraCursor = chCursor.getParagraphCursor(0);

      final wc = TextWordCursor(paraCursor);
      assert(wc.isStartOfParagraph());
      assert(wc.isStartOfText()); // 第一章第一段开头
      assert(wc.chapterIndex == 0);
      assert(wc.paragraphIndex == 0);
      assert(wc.elementIndex == 0);

      // 移动到下一个单词
      wc.moveToNextWord();
      assert(wc.elementIndex == 1);
      assert(!wc.isStartOfParagraph());

      // 移动到段落末尾
      wc.moveToParagraphEnd();
      assert(wc.isEndOfParagraph());

      // 移动到下一段落
      wc.moveToParagraphStart();
      final moved = wc.moveToNextParagraph();
      assert(moved);
      assert(wc.paragraphIndex == 1);
      assert(wc.isStartOfParagraph());

      // 复制光标
      final wc2 = TextWordCursor.copy(wc);
      assert(wc2.paragraphIndex == wc.paragraphIndex);
      assert(wc2.elementIndex == wc.elementIndex);

      return 'navigation: startOfText→move→paraEnd→nextPara(p=${wc
          .paragraphIndex})→copy ✓';
    });

    // 7. TextWordCursor 跨章导航
    await _test('TextWordCursor 跨章导航', () async {
      final plugin = _MockFormatPlugin.twoChapters();
      final model = TextModel(plugin);
      final chCursor = model.getChapterCursor(0);
      // 定位到第一章最后一段末尾
      final lastPara = chCursor.getParagraphCursor(
          chCursor.getParagraphCount() - 1);
      final wc = TextWordCursor(lastPara);
      wc.moveToParagraphEnd();
      assert(wc.isEndOfParagraph());
      // 移动到下一段 → 应跨到第二章
      final moved = wc.moveToNextParagraph();
      assert(moved);
      assert(wc.chapterIndex == 1);
      assert(wc.paragraphIndex == 0);
      return 'cross-chapter: ch0.lastPara.end → ch${wc.chapterIndex}.para${wc
          .paragraphIndex} ✓';
    });

    // 8. TextEngine 分页
    await _test('TextEngine 分页', () async {
      final plugin = _MockFormatPlugin.twoChapters();
      final model = TextModel(plugin);
      final config = TextConfig();
      final engine = TextEngine(config);
      // 模拟一个中等尺寸的视口
      engine.setViewPort(400, 600);
      engine.init(model);

      final controller = engine.pageController;
      assert(controller != null);
      // 应该有当前页
      final curPage = controller!.getCurrentPage();
      assert(curPage != null);
      final pageCount = controller.getCurrentPageCount();
      assert(pageCount > 0);

      return 'viewport=400x600, pageCount=$pageCount, curPage=$curPage ✓';
    });

    // 9. TextEngine preparePage + 行数
    await _test('TextEngine preparePage', () async {
      final plugin = _MockFormatPlugin.twoChapters();
      final model = TextModel(plugin);
      final config = TextConfig();
      final engine = TextEngine(config);
      engine.setViewPort(400, 600);
      engine.init(model);

      final curPage = engine.pageController!.getCurrentPage()!;
      engine.preparePage(curPage);
      assert(curPage.isPrepare);
      final lineCount = curPage.textLineList.length;
      assert(lineCount > 0);

      // 验证行信息合理
      for (final line in curPage.textLineList) {
        assert(line.endElementIndex >= line.startElementIndex);
        assert(line.height > 0 || !line.isVisible);
      }

      return 'lines=$lineCount, allValid ✓';
    });

    // 10. TextEngine prepareTextArea
    await _test('TextEngine prepareTextArea', () async {
      final plugin = _MockFormatPlugin.twoChapters();
      final model = TextModel(plugin);
      final config = TextConfig();
      final engine = TextEngine(config);
      engine.setViewPort(400, 600);
      engine.init(model);

      final curPage = engine.pageController!.getCurrentPage()!;
      engine.preparePage(curPage);
      final labels = engine.prepareTextArea(curPage);
      final areaCount = curPage.textElementAreaVector.size();
      assert(areaCount > 0);
      assert(labels.length == curPage.textLineList.length + 1);

      // 验证 area 坐标合理
      final areas = curPage.textElementAreaVector.areas();
      for (final area in areas) {
        assert(area.length >= 0);
      }

      return 'areas=$areaCount, labels=${labels.length} ✓';
    });

    // 11. TextPageController 翻页
    await _test('TextPageController 翻页', () async {
      final plugin = _MockFormatPlugin.twoChapters();
      final model = TextModel(plugin);
      final config = TextConfig();
      final engine = TextEngine(config);
      engine.setViewPort(400, 600);
      engine.init(model);

      final controller = engine.pageController!;
      final pos0 = controller.getPagePosition(PageType.current);
      assert(pos0 != null);

      // 翻到下一页（如有）
      if (controller.hasPage(PageType.next)) {
        controller.turnPage(PageType.next);
        final pos1 = controller.getPagePosition(PageType.current);
        assert(pos1 != null);
        // 页码应该变化
        assert(pos1!.pageIndex != pos0!.pageIndex ||
            pos1.chapterIndex != pos0.chapterIndex);

        // 翻回上一页
        controller.turnPage(PageType.previous);
        final pos2 = controller.getPagePosition(PageType.current)!;
        assert(pos2.pageIndex == pos0!.pageIndex &&
            pos2.chapterIndex == pos0.chapterIndex);
        return 'turn: $pos0 → $pos1 → $pos2 ✓';
      }
      return 'only 1 page (pos=$pos0), no turn needed ✓';
    });

    // 12. TextPageController 进度
    await _test('TextPageController 进度', () async {
      final plugin = _MockFormatPlugin.twoChapters();
      final model = TextModel(plugin);
      final config = TextConfig();
      final engine = TextEngine(config);
      engine.setViewPort(400, 600);
      engine.init(model);

      final controller = engine.pageController!;
      final progress = controller.getPageProgress(PageType.current)!;
      assert(progress.pageCount > 0);
      assert(progress.pageIndex >= 0);
      assert(progress.pageIndex < progress.pageCount);
      return '$progress ✓';
    });

    // 打印结果到控制台
    debugPrint('\n===== Phase 4 测试结果 =====');
    for (final r in _results) {
      debugPrint(r);
    }
    debugPrint('============================\n');
    setState(() => _isRunning = false);
  }

  Future<void> _test(String name, Future<String> Function() testFn) async {
    try {
      final result = await testFn();
      _results.add('✅ $name: $result');
    } catch (e, st) {
      _results.add('❌ $name: $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Phase 4: 排版引擎验证'),
        backgroundColor: Theme
            .of(context)
            .colorScheme
            .inversePrimary,
      ),
      body: _isRunning
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _results.length,
        itemBuilder: (_, i) =>
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(_results[i], style: const TextStyle(fontSize: 13)),
            ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() => _isRunning = true);
          _runTests();
        },
        child: const Icon(Icons.refresh),
      ),
    );
  }
}

// ==================== Phase 5: 文本渲染测试 ====================

/// 生成长内容测试插件（多页）
class _LongContentMockPlugin extends FormatPlugin {
  final List<TextChapter> _chapters;
  final Map<String, TextContent> _contents;

  _LongContentMockPlugin(this._chapters, this._contents);

  factory _LongContentMockPlugin.create() {
    final chapters = [
      const TextChapter(
          url: 'ch1', title: '第一章 初遇', startIndex: 0, endIndex: 100),
      const TextChapter(
          url: 'ch2', title: '第二章 重逢', startIndex: 100, endIndex: 200),
      const TextChapter(
          url: 'ch3', title: '第三章 离别', startIndex: 200, endIndex: 300),
    ];

    // 第一章: 多段长文本
    final ch1Tags = <TextTag>[
      const TextControlTag(TextControlType.h1, true),
      const TextContentTag('第一章 初遇'),
      const TextControlTag(TextControlType.h1, false),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '人生若只如初见，何事秋风悲画扇。等闲变却故人心，却道故人心易变。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '骊山语罢清宵半，泪雨霖铃终不怨。何如薄幸锦衣郎，比翼连枝当日愿。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '春花秋月何时了，往事知多少。小楼昨夜又东风，故国不堪回首月明中。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '雕栏玉砖应犹在，只是朱颜改。问君能有几多愁，恰似一江春水向东流。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '红豆生南国，春来发几枝。愿君多采撷，此物最相思。这是一首诗，来自唐代诗人王维。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '床前明月光，疑是地上霜。举头望明月，低头思故乡。这是李白最著名的诗篇之一，千古流传。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '白日依山尽，黄河入海流。欲穷千里目，更上一层楼。登鹳雀楼不仅是登高望远，更是一种人生的历练。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '千山鸟飞绝，万径人踪灭。孤舟蓑笠翁，独钓寒江雪。柳宗元的这首诗描绘了一个孤寂而宁静的世界。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '千山鸟飞绝，万径人踪灭。孤舟蓑笠翁，独钓寒江雪。柳宗元的这首诗描绘了一个孤寂而宁静的世界。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '千山鸟飞绝，万径人踪灭。孤舟蓑笠翁，独钓寒江雪。柳宗元的这首诗描绘了一个孤寂而宁静的世界。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '千山鸟飞绝，万径人踪灭。孤舟蓑笠翁，独钓寒江雪。柳宗元的这首诗描绘了一个孤寂而宁静的世界。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '千山鸟飞绝，万径人踪灭。孤舟蓑笠翁，独钓寒江雪。柳宗元的这首诗描绘了一个孤寂而宁静的世界。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '千山鸟飞绝，万径人踪灭。孤舟蓑笠翁，独钓寒江雪。柳宗元的这首诗描绘了一个孤寂而宁静的世界。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '千山鸟飞绝，万径人踪灭。孤舟蓑笠翁，独钓寒江雪。柳宗元的这首诗描绘了一个孤寂而宁静的世界。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '千山鸟飞绝，万径人踪灭。孤舟蓑笠翁，独钓寒江雪。柳宗元的这首诗描绘了一个孤寂而宁静的世界。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '千山鸟飞绝，万径人踪灭。孤舟蓑笠翁，独钓寒江雪。柳宗元的这首诗描绘了一个孤寂而宁静的世界。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '千山鸟飞绝，万径人踪灭。孤舟蓑笠翁，独钓寒江雪。柳宗元的这首诗描绘了一个孤寂而宁静的世界。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '千山鸟飞绝，万径人踪灭。孤舟蓑笠翁，独钓寒江雪。柳宗元的这首诗描绘了一个孤寂而宁静的世界。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '千山鸟飞绝，万径人踪灭。孤舟蓑笠翁，独钓寒江雪。柳宗元的这首诗描绘了一个孤寂而宁静的世界。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '千山鸟飞绝，万径人踪灭。孤舟蓑笠翁，独钓寒江雪。柳宗元的这首诗描绘了一个孤寂而宁静的世界。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '千山鸟飞绝，万径人踪灭。孤舟蓑笠翁，独钓寒江雪。柳宗元的这首诗描绘了一个孤寂而宁静的世界。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '千山鸟飞绝，万径人踪灭。孤舟蓑笠翁，独钓寒江雪。柳宗元的这首诗描绘了一个孤寂而宁静的世界。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '千山鸟飞绝，万径人踪灭。孤舟蓑笠翁，独钓寒江雪。柳宗元的这首诗描绘了一个孤寂而宁静的世界。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '千山鸟飞绝，万径人踪灭。孤舟蓑笠翁，独钓寒江雪。柳宗元的这首诗描绘了一个孤寂而宁静的世界。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '千山鸟飞绝，万径人踪灭。孤舟蓑笠翁，独钓寒江雪。柳宗元的这首诗描绘了一个孤寂而宁静的世界。'),
      const TextParagraphTag(TextParagraphType.textParagraph),

    ];

    // 第二章: 带样式的内容
    final ch2Tags = <TextTag>[
      const TextControlTag(TextControlType.h1, true),
      const TextContentTag('第二章 重逢'),
      const TextControlTag(TextControlType.h1, false),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '去年今日此门中，人面桃花相映红。人面不知何处去，桃花依旧笑春风。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextControlTag(TextControlType.strong, true),
      const TextContentTag('此情可待成追忆，只是当时已惘然。'),
      const TextControlTag(TextControlType.strong, false),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '海内存知己，天涯若比邻。无为在歧路，儿女共沛巾。这是王勃的送别名作，大气磅礴。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextControlTag(TextControlType.emphasis, true),
      const TextContentTag('路漫漫其修远兮，吾将上下而求索。'),
      const TextControlTag(TextControlType.emphasis, false),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '山重水复疑无路，柳暗花明又一村。筄鼓追随春社近，衣冠简朴古风存。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '海内存知己，天涯若比邻。无为在歧路，儿女共沛巾。这是王勃的送别名作，大气磅礴。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextControlTag(TextControlType.emphasis, true),
      const TextContentTag('路漫漫其修远兮，吾将上下而求索。'),
      const TextControlTag(TextControlType.emphasis, false),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '山重水复疑无路，柳暗花明又一村。筄鼓追随春社近，衣冠简朴古风存。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '海内存知己，天涯若比邻。无为在歧路，儿女共沛巾。这是王勃的送别名作，大气磅礴。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextControlTag(TextControlType.emphasis, true),
      const TextContentTag('路漫漫其修远兮，吾将上下而求索。'),
      const TextControlTag(TextControlType.emphasis, false),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '山重水复疑无路，柳暗花明又一村。筄鼓追随春社近，衣冠简朴古风存。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '海内存知己，天涯若比邻。无为在歧路，儿女共沛巾。这是王勃的送别名作，大气磅礴。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextControlTag(TextControlType.emphasis, true),
      const TextContentTag('路漫漫其修远兮，吾将上下而求索。'),
      const TextControlTag(TextControlType.emphasis, false),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '山重水复疑无路，柳暗花明又一村。筄鼓追随春社近，衣冠简朴古风存。'),
      const TextParagraphTag(TextParagraphType.textParagraph),const TextContentTag(
          '海内存知己，天涯若比邻。无为在歧路，儿女共沛巾。这是王勃的送别名作，大气磅礴。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextControlTag(TextControlType.emphasis, true),
      const TextContentTag('路漫漫其修远兮，吾将上下而求索。'),
      const TextControlTag(TextControlType.emphasis, false),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '山重水复疑无路，柳暗花明又一村。筄鼓追随春社近，衣冠简朴古风存。'),
      const TextParagraphTag(TextParagraphType.textParagraph),

    ];

    // 第三章
    final ch3Tags = <TextTag>[
      const TextControlTag(TextControlType.h1, true),
      const TextContentTag('第三章 离别'),
      const TextControlTag(TextControlType.h1, false),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '多情自古伤离别，更那堪冷落清秋节。今宵酒醒何处，杨柳岸晓风残月。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '此去经年，应是良辰好景虚设。便纵有千种风情，更与何人说。柳永的词豪放不羁，词中充满了旅人的惆怅。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '大江东去，浪淂尽千古风流人物。故垒西边，人道是三国周郎赤壁。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '乱石穿空，惊涛拍岸，卷起千堆雪。江山如画，一时多少豪杰。苏轼的豪迈与历史的叹息交织在一起。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '遥想公瑾当年，小乔初嫁了，雄姿英发。羽扇纶巾，谈笑间樽橹灰飞烟灭。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '此去经年，应是良辰好景虚设。便纵有千种风情，更与何人说。柳永的词豪放不羁，词中充满了旅人的惆怅。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '大江东去，浪淂尽千古风流人物。故垒西边，人道是三国周郎赤壁。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '乱石穿空，惊涛拍岸，卷起千堆雪。江山如画，一时多少豪杰。苏轼的豪迈与历史的叹息交织在一起。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '遥想公瑾当年，小乔初嫁了，雄姿英发。羽扇纶巾，谈笑间樽橹灰飞烟灭。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '此去经年，应是良辰好景虚设。便纵有千种风情，更与何人说。柳永的词豪放不羁，词中充满了旅人的惆怅。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '大江东去，浪淂尽千古风流人物。故垒西边，人道是三国周郎赤壁。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '乱石穿空，惊涛拍岸，卷起千堆雪。江山如画，一时多少豪杰。苏轼的豪迈与历史的叹息交织在一起。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '遥想公瑾当年，小乔初嫁了，雄姿英发。羽扇纶巾，谈笑间樽橹灰飞烟灭。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '此去经年，应是良辰好景虚设。便纵有千种风情，更与何人说。柳永的词豪放不羁，词中充满了旅人的惆怅。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '大江东去，浪淂尽千古风流人物。故垒西边，人道是三国周郎赤壁。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '乱石穿空，惊涛拍岸，卷起千堆雪。江山如画，一时多少豪杰。苏轼的豪迈与历史的叹息交织在一起。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '遥想公瑾当年，小乔初嫁了，雄姿英发。羽扇纶巾，谈笑间樽橹灰飞烟灭。'),
      const TextParagraphTag(TextParagraphType.textParagraph), const TextContentTag(
          '此去经年，应是良辰好景虚设。便纵有千种风情，更与何人说。柳永的词豪放不羁，词中充满了旅人的惆怅。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '大江东去，浪淂尽千古风流人物。故垒西边，人道是三国周郎赤壁。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '乱石穿空，惊涛拍岸，卷起千堆雪。江山如画，一时多少豪杰。苏轼的豪迈与历史的叹息交织在一起。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '遥想公瑾当年，小乔初嫁了，雄姿英发。羽扇纶巾，谈笑间樽橹灰飞烟灭。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '此去经年，应是良辰好景虚设。便纵有千种风情，更与何人说。柳永的词豪放不羁，词中充满了旅人的惆怅。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '大江东去，浪淂尽千古风流人物。故垒西边，人道是三国周郎赤壁。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '乱石穿空，惊涛拍岸，卷起千堆雪。江山如画，一时多少豪杰。苏轼的豪迈与历史的叹息交织在一起。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '遥想公瑾当年，小乔初嫁了，雄姿英发。羽扇纶巾，谈笑间樽橹灰飞烟灭。'),
      const TextParagraphTag(TextParagraphType.textParagraph), const TextContentTag(
          '此去经年，应是良辰好景虚设。便纵有千种风情，更与何人说。柳永的词豪放不羁，词中充满了旅人的惆怅。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '大江东去，浪淂尽千古风流人物。故垒西边，人道是三国周郎赤壁。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '乱石穿空，惊涛拍岸，卷起千堆雪。江山如画，一时多少豪杰。苏轼的豪迈与历史的叹息交织在一起。'),
      const TextParagraphTag(TextParagraphType.textParagraph),
      const TextContentTag(
          '遥想公瑾当年，小乔初嫁了，雄姿英发。羽扇纶巾，谈笑间樽橹灰飞烟灭。'),
      const TextParagraphTag(TextParagraphType.textParagraph),


    ];

    return _LongContentMockPlugin(chapters, {
      'ch1': TextContent(tags: ch1Tags),
      'ch2': TextContent(tags: ch2Tags),
      'ch3': TextContent(tags: ch3Tags),
    });
  }

  @override
  Future<void> openBook(String bookPath) async {}

  @override
  String getEncoding() => 'utf-8';

  @override
  String getLanguage() => 'zh';

  @override
  List<TextChapter> getChapters() => _chapters;

  @override
  TextContent? getChapterContent(TextChapter chapter) => _contents[chapter.url];

  @override
  String? getChapterPlainText(TextChapter chapter) => null;

  @override
  void release() {}
}

class Phase5TestApp extends StatelessWidget {
  const Phase5TestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NBReader - Phase 5 Test',
      theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo)),
      home: const Phase5TestPage(),
    );
  }
}

class Phase5TestPage extends StatefulWidget {
  const Phase5TestPage({super.key});

  @override
  State<Phase5TestPage> createState() => _Phase5TestPageState();
}

class _Phase5TestPageState extends State<Phase5TestPage> {
  late TextModel _model;
  final _readerKey = GlobalKey<TextReaderWidgetState>();
  String _statusText = '加载中...';

  @override
  void initState() {
    super.initState();
    final plugin = _LongContentMockPlugin.create();
    _model = TextModel(plugin);
  }

  void _onPageChanged(PagePosition pos, PageProgress progress) {
    setState(() {
      _statusText = '第${pos.chapterIndex + 1}章 | '
          '页 ${progress.pageIndex + 1}/${progress.pageCount}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // 顶部状态栏
          Container(
            color: Colors.indigo,
            padding: EdgeInsets.only(
              top: MediaQuery
                  .of(context)
                  .padding
                  .top,
              left: 16, right: 16, bottom: 8,
            ),
            child: Row(
              children: [
                const Text('Phase 5: 文本渲染',
                    style: TextStyle(color: Colors.white, fontSize: 16)),
                const Spacer(),
                Text(_statusText,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
          // 阅读器主体
          Expanded(
            child: TextReaderWidget(
              key: _readerKey,
              textModel: _model,
              onPageChanged: _onPageChanged,
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== Phase 6: 翻页动画测试 ====================

class Phase6TestApp extends StatelessWidget {
  const Phase6TestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NBReader - Phase 6 Test',
      theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
      home: const Phase6TestPage(),
    );
  }
}

class Phase6TestPage extends StatefulWidget {
  const Phase6TestPage({super.key});

  @override
  State<Phase6TestPage> createState() => _Phase6TestPageState();
}

class _Phase6TestPageState extends State<Phase6TestPage> {
  late TextModel _model;
  final _readerKey = GlobalKey<TextReaderWidgetState>();
  String _statusText = '加载中...';
  PageAnimType _animType = PageAnimType.slide;

  @override
  void initState() {
    super.initState();
    final plugin = _LongContentMockPlugin.create();
    _model = TextModel(plugin);
  }

  void _onPageChanged(PagePosition pos, PageProgress progress) {
    setState(() {
      _statusText = '第${pos.chapterIndex + 1}章 | '
          '页 ${progress.pageIndex + 1}/${progress.pageCount}';
    });
  }

  void _switchAnim(PageAnimType type) {
    setState(() => _animType = type);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // 顶部状态栏
          Container(
            color: Colors.deepPurple,
            padding: EdgeInsets.only(
              top: MediaQuery
                  .of(context)
                  .padding
                  .top,
              left: 16, right: 16, bottom: 8,
            ),
            child: Row(
              children: [
                const Text('Phase 6: 翻页动画',
                    style: TextStyle(color: Colors.white, fontSize: 16)),
                const Spacer(),
                Text(_statusText,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
          // 动画类型选择器
          Container(
            color: Colors.deepPurple.shade100,
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _animButton('无', PageAnimType.none),
                _animButton('滑动', PageAnimType.slide),
                _animButton('覆盖', PageAnimType.cover),
                _animButton('仿真', PageAnimType.simulation),
                _animButton('滚动', PageAnimType.scroll),
              ],
            ),
          ),
          // 阅读器主体
          Expanded(
            child: TextReaderWidget(
              key: _readerKey,
              textModel: _model,
              animType: _animType,
              onPageChanged: _onPageChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _animButton(String label, PageAnimType type) {
    final isSelected = _animType == type;
    return TextButton(
      onPressed: () => _switchAnim(type),
      style: TextButton.styleFrom(
        backgroundColor: isSelected ? Colors.deepPurple : Colors.transparent,
        foregroundColor: isSelected ? Colors.white : Colors.deepPurple,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minimumSize: Size.zero,
      ),
      child: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }
}
