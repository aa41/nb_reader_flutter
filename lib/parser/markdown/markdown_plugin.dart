import 'dart:io';

import 'package:path/path.dart' as p;

import '../../text/entity/text_chapter.dart';
import '../../text/entity/text_content.dart';
import '../format_plugin.dart';
import 'markdown_reader.dart';

/// Markdown 格式解析插件
/// 支持 .md / .markdown 文件阅读
///
/// 特性：
/// - 按 # / ## 标题自动拆分章节
/// - 语法高亮（代码块）
/// - 表格渲染（图片/文本回退）
/// - 本地图片加载
/// - 粗体、斜体、删除线、引用、列表等
class MarkdownPlugin implements FormatPlugin {
  String? _bookPath;
  String _fullText = '';
  List<TextChapter> _chapters = [];
  String _basePath = '';

  @override
  Future<void> openBook(String bookPath) async {
    _bookPath = bookPath;
    _basePath = p.dirname(bookPath);

    final file = File(bookPath);
    if (!await file.exists()) {
      throw FileSystemException('File not found', bookPath);
    }

    _fullText = await file.readAsString();
    _buildChapters();
  }

  /// 按标题拆分章节
  void _buildChapters() {
    _chapters.clear();

    // 匹配 # 或 ## 开头的行作为章节分隔
    final lines = _fullText.split('\n');
    final chapterStarts = <int>[]; // 行号
    final chapterTitles = <String>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trimRight();
      if (line.startsWith('# ') || line.startsWith('## ')) {
        chapterStarts.add(i);
        // 去掉 # 前缀
        chapterTitles.add(line.replaceFirst(RegExp(r'^#{1,2}\s+'), '').trim());
      }
    }

    if (chapterStarts.isEmpty) {
      // 没有标题，整个文件作为单章节
      final title = _extractTitle() ?? p.basenameWithoutExtension(_bookPath!);
      _chapters.add(TextChapter(
        url: _bookPath!,
        title: title,
        startIndex: 0,
        endIndex: _fullText.length,
      ));
      return;
    }

    // 如果第一个标题不在文件开头，把前面的内容作为序章
    if (chapterStarts.first > 0) {
      final prologueEnd = _lineOffset(lines, chapterStarts.first);
      final prologueText = _fullText.substring(0, prologueEnd).trim();
      if (prologueText.isNotEmpty) {
        chapterStarts.insert(0, 0);
        chapterTitles.insert(0, '前言');
      }
    }

    for (int i = 0; i < chapterStarts.length; i++) {
      final startOffset = _lineOffset(lines, chapterStarts[i]);
      final endOffset = i + 1 < chapterStarts.length
          ? _lineOffset(lines, chapterStarts[i + 1])
          : _fullText.length;

      _chapters.add(TextChapter(
        url: _bookPath!,
        title: chapterTitles[i],
        startIndex: startOffset,
        endIndex: endOffset,
      ));
    }
  }

  /// 计算行号对应的字符偏移
  int _lineOffset(List<String> lines, int lineIndex) {
    int offset = 0;
    for (int i = 0; i < lineIndex && i < lines.length; i++) {
      offset += lines[i].length + 1; // +1 for '\n'
    }
    return offset.clamp(0, _fullText.length);
  }

  /// 尝试从文件内容提取标题（第一个 # 标题）
  String? _extractTitle() {
    final match = RegExp(r'^#\s+(.+)$', multiLine: true).firstMatch(_fullText);
    return match?.group(1)?.trim();
  }

  @override
  String getEncoding() => 'utf-8';

  @override
  String getLanguage() => '';

  @override
  List<TextChapter> getChapters() => _chapters;

  @override
  TextContent? getChapterContent(TextChapter chapter) {
    if (_fullText.isEmpty) return null;

    final start = chapter.startIndex.clamp(0, _fullText.length);
    final end = chapter.endIndex.clamp(start, _fullText.length);
    final chapterText = _fullText.substring(start, end);

    final reader = MarkdownReader(basePath: _basePath);
    return reader.parse(chapterText);
  }

  @override
  ImageDataResolver? get imageDataResolver {
    return (String imagePath) {
      // 网络图片由图片缓存层异步下载，这里返回 null
      if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
        return null;
      }
      // 解析相对于 .md 文件的路径
      final fullPath = p.isAbsolute(imagePath)
          ? imagePath
          : p.normalize('$_basePath/$imagePath');
      final file = File(fullPath);
      if (file.existsSync()) {
        return file.readAsBytesSync();
      }
      return null;
    };
  }

  @override
  void release() {
    _bookPath = null;
    _fullText = '';
    _chapters = [];
  }
}
