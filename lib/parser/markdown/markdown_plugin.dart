import 'dart:io';

import 'package:path/path.dart' as p;

import '../../text/entity/text_chapter.dart';
import '../../text/entity/text_content.dart';
import '../format_plugin.dart';
import 'markdown_content_reader.dart';

/// Markdown 格式解析插件
///
/// Markdown 文件通常不分章节，但此处按一级标题 `# ` 拆分章节。
/// 若文件中无一级标题，则整个文件视为单章。
class MarkdownPlugin implements FormatPlugin {
  String? _bookPath;
  String? _basePath;
  String? _rawContent;
  List<TextChapter> _chapters = [];

  /// 按一级标题拆分的原始文本段
  List<String> _chapterTexts = [];

  @override
  Future<void> openBook(String bookPath) async {
    _bookPath = bookPath;
    _basePath = p.dirname(bookPath);

    final file = File(bookPath);
    _rawContent = await file.readAsString();

    _buildChapters();
  }

  /// 按一级标题（`# `）拆分章节
  void _buildChapters() {
    final content = _rawContent ?? '';
    _chapters = [];
    _chapterTexts = [];

    // 正则匹配行首 `# ` 作为章节分隔
    final lines = content.split('\n');
    final chapterStarts = <int>[]; // 行索引
    final chapterTitles = <String>[];

    bool inFencedCodeBlock = false;
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trimRight();
      // 跟踪围栏代码块状态（``` 或 ~~~）
      if (line.startsWith('```') || line.startsWith('~~~')) {
        inFencedCodeBlock = !inFencedCodeBlock;
        continue;
      }
      // ATX 标题：以 `# ` 开头（仅一级标题作为章节分隔）
      // 必须在围栏代码块外才作为章节分隔
      if (!inFencedCodeBlock &&
          line.startsWith('# ') && !line.startsWith('## ')) {
        chapterStarts.add(i);
        chapterTitles.add(line.substring(2).trim());
      }
    }

    if (chapterStarts.isEmpty) {
      // 无一级标题 → 整文件单章
      final title = p.basenameWithoutExtension(_bookPath ?? 'Untitled');
      _chapters.add(TextChapter(
        url: '0',
        title: title,
        startIndex: 0,
        endIndex: 0,
      ));
      _chapterTexts.add(content);
    } else {
      // 检查一级标题前是否有内容（前言）
      if (chapterStarts.first > 0) {
        final preface = lines.sublist(0, chapterStarts.first).join('\n').trim();
        if (preface.isNotEmpty) {
          _chapters.add(TextChapter(
            url: '0',
            title: '前言',
            startIndex: 0,
            endIndex: 0,
          ));
          _chapterTexts.add(preface);
        }
      }

      for (int i = 0; i < chapterStarts.length; i++) {
        final start = chapterStarts[i];
        final end = (i + 1 < chapterStarts.length)
            ? chapterStarts[i + 1]
            : lines.length;
        final chapterText = lines.sublist(start, end).join('\n');

        _chapters.add(TextChapter(
          url: '${_chapters.length}',
          title: chapterTitles[i],
          startIndex: _chapters.length,
          endIndex: _chapters.length,
        ));
        _chapterTexts.add(chapterText);
      }
    }
  }

  @override
  String getEncoding() => 'utf-8';

  @override
  String getLanguage() => '';

  @override
  List<TextChapter> getChapters() => _chapters;

  @override
  TextContent? getChapterContent(TextChapter chapter) {
    final idx = _chapters.indexOf(chapter);
    if (idx < 0 || idx >= _chapterTexts.length) return null;

    return MarkdownContentReader.parse(
      _chapterTexts[idx],
      basePath: _basePath,
    );
  }

  @override
  String? getChapterPlainText(TextChapter chapter) {
    final content = getChapterContent(chapter);
    if (content == null) return null;
    return content.toPlainText();
  }

  @override
  ImageDataResolver? get imageDataResolver {
    return (String imagePath) {
      // 尝试相对路径
      if (_basePath != null) {
        final resolved = p.normalize('$_basePath/$imagePath');
        final file = File(resolved);
        if (file.existsSync()) {
          return file.readAsBytesSync();
        }
      }
      // 尝试绝对路径
      final file = File(imagePath);
      if (file.existsSync()) {
        return file.readAsBytesSync();
      }
      return null;
    };
  }

  @override
  void release() {
    _bookPath = null;
    _basePath = null;
    _rawContent = null;
    _chapters = [];
    _chapterTexts = [];
  }
}
