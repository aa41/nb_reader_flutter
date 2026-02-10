/// 文本元素基类 - 段落内的最小渲染单元
abstract class TextElement {
  const TextElement();

  /// 水平空格（允许换行）
  static const TextElement hSpace = _HSpaceElement();

  /// 不换行空格
  static const TextElement nbSpace = _NBSpaceElement();

  /// 缩进
  static const TextElement indent = _IndentElement();

  /// 样式闭合
  static const TextElement styleClose = _StyleCloseElement();

  /// 段落后标记
  static const TextElement afterParagraph = _AfterParagraphElement();
}

class _HSpaceElement extends TextElement {
  const _HSpaceElement();
  @override
  String toString() => 'HSpace';
}

class _NBSpaceElement extends TextElement {
  const _NBSpaceElement();
  @override
  String toString() => 'NBSpace';
}

class _IndentElement extends TextElement {
  const _IndentElement();
  @override
  String toString() => 'Indent';
}

class _StyleCloseElement extends TextElement {
  const _StyleCloseElement();
  @override
  String toString() => 'StyleClose';
}

class _AfterParagraphElement extends TextElement {
  const _AfterParagraphElement();
  @override
  String toString() => 'AfterParagraph';
}
