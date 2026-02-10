import 'book_type.dart';

/// 书籍实体
class BookEntity {
  final String id;
  final String title;
  final String url; // 文件路径
  final BookType type;
  final String? author;
  final String? coverPath;
  final DateTime? lastReadTime;
  final int? lastChapterIndex;
  /// 精确文本位置（段落+元素+字符索引），用于跨配置变更的准确恢复
  final int? lastParagraphIndex;
  final int? lastElementIndex;
  final int? lastCharIndex;

  const BookEntity({
    required this.id,
    required this.title,
    required this.url,
    required this.type,
    this.author,
    this.coverPath,
    this.lastReadTime,
    this.lastChapterIndex,
    this.lastParagraphIndex,
    this.lastElementIndex,
    this.lastCharIndex,
  });

  BookEntity copyWith({
    String? title,
    BookType? type,
    String? author,
    String? coverPath,
    DateTime? lastReadTime,
    int? lastChapterIndex,
    int? lastParagraphIndex,
    int? lastElementIndex,
    int? lastCharIndex,
  }) {
    return BookEntity(
      id: id,
      title: title ?? this.title,
      url: url,
      type: type ?? this.type,
      author: author ?? this.author,
      coverPath: coverPath ?? this.coverPath,
      lastReadTime: lastReadTime ?? this.lastReadTime,
      lastChapterIndex: lastChapterIndex ?? this.lastChapterIndex,
      lastParagraphIndex: lastParagraphIndex ?? this.lastParagraphIndex,
      lastElementIndex: lastElementIndex ?? this.lastElementIndex,
      lastCharIndex: lastCharIndex ?? this.lastCharIndex,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'url': url,
      'type': type.name,
      'author': author,
      'coverPath': coverPath,
      'lastReadTime': lastReadTime?.millisecondsSinceEpoch,
      'lastChapterIndex': lastChapterIndex,
      'lastParagraphIndex': lastParagraphIndex,
      'lastElementIndex': lastElementIndex,
      'lastCharIndex': lastCharIndex,
    };
  }

  factory BookEntity.fromJson(Map<String, dynamic> json) {
    return BookEntity(
      id: json['id'] as String,
      title: json['title'] as String,
      url: json['url'] as String,
      type: BookType.values.firstWhere((e) => e.name == json['type']),
      author: json['author'] as String?,
      coverPath: json['coverPath'] as String?,
      lastReadTime: json['lastReadTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['lastReadTime'] as int)
          : null,
      lastChapterIndex: json['lastChapterIndex'] as int?,
      lastParagraphIndex: json['lastParagraphIndex'] as int?,
      lastElementIndex: json['lastElementIndex'] as int?,
      lastCharIndex: json['lastCharIndex'] as int?,
    );
  }

  @override
  String toString() =>
      'BookEntity(id=$id, title=$title, type=$type, url=$url)';
}
