import 'dart:typed_data';
import 'dart:ui' as ui;
import 'text_element.dart';

/// 图片元素
class TextImageElement extends TextElement {
  final TextImage image;

  const TextImageElement(this.image);

  @override
  String toString() => 'TextImageElement(${image.id})';
}

/// 图片资源
class TextImage {
  final String id;
  final String? mimeType;
  final Uint8List? data;
  final String? filePath; // EPUB 中的文件路径
  ui.Image? decodedImage; // 解码后的图片缓存

  TextImage({
    required this.id,
    this.mimeType,
    this.data,
    this.filePath,
    this.decodedImage,
  });

  @override
  String toString() => 'TextImage(id=$id, mime=$mimeType, hasData=${data != null})';
}
