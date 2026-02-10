/// 章节信息数据
class TextChapter {
  final String url;
  final String title;
  final int startIndex; // 在源文件中的起始偏移
  final int endIndex; // 在源文件中的结束偏移，-1 表示到文件末尾

  const TextChapter({
    required this.url,
    required this.title,
    required this.startIndex,
    required this.endIndex,
  });

  @override
  String toString() =>
      'TextChapter(url=$url, title=$title, start=$startIndex, end=$endIndex)';
}
