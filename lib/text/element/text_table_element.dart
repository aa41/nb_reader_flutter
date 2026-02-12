import 'text_element.dart';

/// 表格对齐方式
class TableAlignment {
  static const int left = 0;
  static const int center = 1;
  static const int right = 2;
}

/// 表格元素 — 整表参与分页和渲染
class TextTableElement extends TextElement {
  /// 表头
  final List<String> headers;

  /// 数据行
  final List<List<String>> rows;

  /// 各列对齐方式
  final List<int> alignments;

  /// 表格内边距
  static const int cellPaddingH = 12;
  static const int cellPaddingV = 8;

  /// 表格外边距（上下）— 与相邻内容的间距
  static const int outerMarginV = 12;

  /// 表格圆角
  static const double borderRadius = 4.0;

  /// 表格边框宽度
  static const double borderWidth = 1.0;

  const TextTableElement({
    required this.headers,
    required this.rows,
    required this.alignments,
  });

  /// 总列数
  int get columnCount => headers.length;

  /// 总行数（含表头）
  int get totalRowCount => 1 + rows.length;

  @override
  String toString() => 'TextTableElement(cols=$columnCount, rows=${rows.length})';
}
