/// 文本度量信息，用于解决 px/em/rem 换算
class TextMetrics {
  final int dpi;
  final int screenWidth;
  final int screenHeight;
  final int baseFontSize;

  const TextMetrics({
    required this.dpi,
    required this.screenWidth,
    required this.screenHeight,
    required this.baseFontSize,
  });

  @override
  String toString() =>
      'TextMetrics(dpi=$dpi, ${screenWidth}x$screenHeight, fontSize=$baseFontSize)';
}
