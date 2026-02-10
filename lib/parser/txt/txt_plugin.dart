import 'dart:io';
import 'dart:typed_data';

import '../format_plugin.dart';
import '../encoding/encoding_detector.dart';
import '../../text/entity/text_chapter.dart';
import '../../text/entity/text_content.dart';
import 'plain_text_format.dart';
import 'txt_chapter_detector.dart';
import 'txt_reader.dart';

/// TXT 格式解析插件
/// 完整流程：读取文件 → 检测编码 → 解码 → 探测格式 → 章节分割 → 内容解析
class TxtPlugin implements FormatPlugin {
  String? _bookPath;
  String _encoding = '';
  String _decodedText = '';
  PlainTextFormat? _format;
  List<TextChapter>? _chapters;

  /// 章节匹配正则
  String? _chapterPattern;

  /// 序章标题
  String _prologueTitle = '开始';

  /// 设置章节检测配置
  void setConfigure({String? chapterPattern, String? prologueTitle}) {
    _chapterPattern = chapterPattern;
    if (prologueTitle != null) _prologueTitle = prologueTitle;
  }

  @override
  Future<void> openBook(String bookPath) async {
    if (_bookPath == bookPath) return;

    release();
    _bookPath = bookPath;

    // 1. 读取文件字节
    final file = File(bookPath);
    if (!await file.exists()) {
      throw FileSystemException('File not found', bookPath);
    }
    final bytes = Uint8List.fromList(await file.readAsBytes());

    // 2. 检测编码
    _encoding = EncodingDetector.detect(bytes);

    // 3. 解码为字符串
    _decodedText = EncodingDetector.decode(bytes, _encoding);

    // 4. 探测文本格式
    _format = PlainTextDetector.detect(_decodedText);
  }

  @override
  String getEncoding() => _encoding;

  @override
  String getLanguage() => 'zh';

  @override
  List<TextChapter> getChapters() {
    if (_decodedText.isEmpty) return [];

    _chapters ??= TxtChapterDetector.detect(
      _decodedText,
      _bookPath!,
      pattern: _chapterPattern,
      prologueTitle: _prologueTitle,
    );

    return _chapters!;
  }

  @override
  TextContent? getChapterContent(TextChapter chapter) {
    if (_decodedText.isEmpty || _format == null) return null;

    // 提取章节文本
    final start = chapter.startIndex.clamp(0, _decodedText.length);
    final end = chapter.endIndex.clamp(start, _decodedText.length);
    final chapterText = _decodedText.substring(start, end);

    // 判断是否有标题行（非序章的章节第一行为标题）
    final hasTitleLine = chapter.title != _prologueTitle;

    return TxtReader.parse(chapterText, _format!, hasTitleLine: hasTitleLine);
  }

  @override
  ImageDataResolver? get imageDataResolver => null;

  @override
  void release() {
    _bookPath = null;
    _encoding = '';
    _decodedText = '';
    _format = null;
    _chapters = null;
  }
}
