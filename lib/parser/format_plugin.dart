import 'dart:typed_data';

import '../text/entity/text_chapter.dart';
import '../text/entity/text_content.dart';

/// 图片数据解析器类型
typedef ImageDataResolver = Uint8List? Function(String imagePath);

/// 格式解析插件抽象接口
abstract class FormatPlugin {
  /// 打开书籍（异步读取文件）
  Future<void> openBook(String bookPath);

  /// 获取检测到的编码
  String getEncoding();

  /// 获取语言
  String getLanguage();

  /// 获取章节列表
  List<TextChapter> getChapters();

  /// 获取章节内容（直接输出 TextTag 列表，无二进制中间格式）
  TextContent? getChapterContent(TextChapter chapter);

  /// 获取图片数据解析器（用于 EPUB 等格式内嵌图片的加载）
  ImageDataResolver? get imageDataResolver => null;

  /// 释放资源
  void release();
}
