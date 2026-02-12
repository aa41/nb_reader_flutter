import '../entity/text_position.dart';

/// 标注类型
enum TextAnnotationKind {
  highlight,
  note,
}

/// 标注样式类型
enum TextAnnotationStyleType {
  /// 背景高亮
  background,

  /// 下划线
  underline,

  /// 波浪下划线
  wavyUnderline,

  /// 虚线下划线（用于想法）
  dashedUnderline,
}

class TextAnnotationStyle {
  final TextAnnotationStyleType type;

  /// ARGB int
  final int color;

  const TextAnnotationStyle({
    required this.type,
    required this.color,
  });

  TextAnnotationStyle copyWith({
    TextAnnotationStyleType? type,
    int? color,
  }) {
    return TextAnnotationStyle(
      type: type ?? this.type,
      color: color ?? this.color,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'color': color,
    };
  }

  factory TextAnnotationStyle.fromJson(Map<String, dynamic> json) {
    return TextAnnotationStyle(
      type: TextAnnotationStyleType.values
          .firstWhere((e) => e.name == (json['type'] as String)),
      color: json['color'] as int,
    );
  }
}

/// 文本标注（高亮 / 想法）
class TextAnnotation {
  final String id;
  final TextAnnotationKind kind;

  /// 标注范围：使用 TextFixedPosition（段落+元素+字符边界）
  /// 约定：start <= end（end 为“右开区间”边界）
  final TextFixedPosition start;
  final TextFixedPosition end;

  final TextAnnotationStyle style;

  /// 仅 kind=note 时有值
  final String? noteText;

  /// 毫秒时间戳
  final int createdAt;
  final int updatedAt;

  TextAnnotation({
    required this.id,
    required this.kind,
    required this.start,
    required this.end,
    required this.style,
    this.noteText,
    required this.createdAt,
    required this.updatedAt,
  });

  TextAnnotation copyWith({
    TextAnnotationKind? kind,
    TextFixedPosition? start,
    TextFixedPosition? end,
    TextAnnotationStyle? style,
    String? noteText,
    int? updatedAt,
  }) {
    return TextAnnotation(
      id: id,
      kind: kind ?? this.kind,
      start: start ?? this.start,
      end: end ?? this.end,
      style: style ?? this.style,
      noteText: noteText ?? this.noteText,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 返回一个确保 start<=end 的副本
  TextAnnotation normalized() {
    final (s, e) = normalizeRange(start, end);
    if (identical(s, start) && identical(e, end)) return this;
    return copyWith(start: s, end: e);
  }

  static (TextFixedPosition, TextFixedPosition) normalizeRange(
      TextFixedPosition a, TextFixedPosition b) {
    if (a.compareTo(b) <= 0) return (a, b);
    return (b, a);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'kind': kind.name,
      'start': _posToJson(start),
      'end': _posToJson(end),
      'style': style.toJson(),
      'noteText': noteText,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  factory TextAnnotation.fromJson(Map<String, dynamic> json) {
    return TextAnnotation(
      id: json['id'] as String,
      kind: TextAnnotationKind.values
          .firstWhere((e) => e.name == (json['kind'] as String)),
      start: _posFromJson(json['start'] as Map<String, dynamic>),
      end: _posFromJson(json['end'] as Map<String, dynamic>),
      style: TextAnnotationStyle.fromJson(json['style'] as Map<String, dynamic>),
      noteText: json['noteText'] as String?,
      createdAt: json['createdAt'] as int,
      updatedAt: json['updatedAt'] as int,
    ).normalized();
  }

  @override
  String toString() =>
      'TextAnnotation(id=$id, kind=$kind, start=$start, end=$end, style=${style.type})';
}

Map<String, dynamic> _posToJson(TextFixedPosition p) {
  return {
    'chapterIndex': p.chapterIndex,
    'paragraphIndex': p.paragraphIndex,
    'elementIndex': p.elementIndex,
    'charIndex': p.charIndex,
  };
}

TextFixedPosition _posFromJson(Map<String, dynamic> json) {
  return TextFixedPosition(
    chapterIndex: json['chapterIndex'] as int,
    paragraphIndex: json['paragraphIndex'] as int,
    elementIndex: json['elementIndex'] as int,
    charIndex: json['charIndex'] as int,
  );
}
