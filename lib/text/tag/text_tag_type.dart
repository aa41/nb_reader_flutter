/// 文本标签类型
class TextTagType {
  static const int text = 1;
  static const int image = 2;
  static const int control = 3;
  static const int hyperlinkControl = 4;
  static const int styleCss = 5;
  static const int styleOther = 6;
  static const int styleClose = 7;
  static const int fixedHSpace = 8;
  static const int resetBidi = 9;
  static const int audio = 10;
  static const int video = 11;
  static const int extension_ = 12;
  static const int paragraph = 13;
}

/// 段落类型
class TextParagraphType {
  static const int textParagraph = 0;
  static const int emptyLineParagraph = 2;
  static const int beforeSkipParagraph = 3;
  static const int afterSkipParagraph = 4;
  static const int endOfSectionParagraph = 5;
  static const int pseudoEndOfSectionParagraph = 6;
  static const int endOfTextParagraph = 7;
  static const int encryptedSectionParagraph = 8;
}

/// 控制标签子类型（对应 HTML 标签映射）
class TextControlType {
  static const int regular = 0;
  static const int h1 = 1;
  static const int h2 = 2;
  static const int h3 = 3;
  static const int h4 = 4;
  static const int h5 = 5;
  static const int h6 = 6;
  static const int strong = 7;
  static const int bold = 8;
  static const int emphasis = 9;
  static const int italic = 10;
  static const int code = 11;
  static const int tt = 12;
  static const int keyboard = 13;
  static const int variable = 14;
  static const int samp = 15;
  static const int cite = 16;
  static const int superscript = 17;
  static const int subscript = 18;
  static const int dd = 19;
  static const int dfn = 20;
  static const int strike = 21;
  static const int preformatted = 22;
  static const int paragraph = 23;
  static const int title = 24; // TXT 章节标题
  static const int image = 25;

  // === Markdown 扩展 ===
  static const int blockquote = 30;       // 引用块
  static const int highlight = 31;        // ==高亮==
  static const int link = 32;             // 链接文字
  static const int codeBlockLine = 33;    // 代码块行
  static const int tableCell = 34;        // 表格单元格
  static const int tableHeaderCell = 35;  // 表头单元格
  static const int horizontalRule = 36;   // 分割线
  static const int imageCaption = 37;     // 图片说明
  static const int taskChecked = 38;      // 任务列表（已勾选）
  static const int taskUnchecked = 39;    // 任务列表（未勾选）
  static const int kbd = 40;              // 键盘按键
  static const int footnoteRef = 41;      // 脚注引用
  static const int underline = 42;        // 下划线
}
