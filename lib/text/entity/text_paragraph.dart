/// 文本段落
class TextParagraph {
  final int type; // TextParagraphType
  final int indexFromChapter; // 段落在章节中的索引
  final int startOffset; // 段落在 tag 列表中的起始偏移
  final int endOffset; // 段落在 tag 列表中的终止偏移

  const TextParagraph({
    required this.type,
    required this.indexFromChapter,
    required this.startOffset,
    required this.endOffset,
  });

  @override
  String toString() =>
      'TextParagraph(type=$type, index=$indexFromChapter, start=$startOffset, end=$endOffset)';
}
