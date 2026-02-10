/// 代码语法高亮器
/// 基于正则的 tokenizer，支持常见语言的关键字/字符串/注释/数字着色
class CodeHighlighter {
  /// Token 颜色主题
  static const int colorKeyword = 0xFF0033B3;    // 蓝色 — 关键字
  static const int colorString = 0xFF067D17;     // 绿色 — 字符串
  static const int colorComment = 0xFF8C8C8C;    // 灰色 — 注释
  static const int colorNumber = 0xFF1750EB;     // 蓝色 — 数字
  static const int colorType = 0xFF871094;       // 紫色 — 类型/类名
  static const int colorPunctuation = 0xFF333333; // 默认 — 标点
  static const int colorDefault = 0xFF333333;    // 默认文本

  /// 高亮代码块，返回 (文本, 颜色?) 列表
  static List<HighlightToken> highlight(String code, String? language) {
    final lang = (language ?? '').toLowerCase();
    final keywords = _getKeywords(lang);
    final types = _getTypes(lang);
    final singleLineComment = _getSingleLineComment(lang);
    final multiLineComment = _getMultiLineComment(lang);

    if (keywords.isEmpty) {
      // 未知语言，不高亮
      return [HighlightToken(code, null)];
    }

    return _tokenize(code, keywords, types, singleLineComment, multiLineComment);
  }

  static List<HighlightToken> _tokenize(
    String code,
    Set<String> keywords,
    Set<String> types,
    String? singleLineComment,
    List<String>? multiLineComment,
  ) {
    final tokens = <HighlightToken>[];
    final len = code.length;
    var i = 0;
    final buf = StringBuffer();

    void flushBuffer() {
      if (buf.isNotEmpty) {
        tokens.add(HighlightToken(buf.toString(), null));
        buf.clear();
      }
    }

    while (i < len) {
      // 多行注释
      if (multiLineComment != null &&
          i + multiLineComment[0].length <= len &&
          code.substring(i, i + multiLineComment[0].length) == multiLineComment[0]) {
        flushBuffer();
        final endIdx = code.indexOf(multiLineComment[1], i + multiLineComment[0].length);
        final end = endIdx == -1 ? len : endIdx + multiLineComment[1].length;
        tokens.add(HighlightToken(code.substring(i, end), colorComment));
        i = end;
        continue;
      }

      // 单行注释
      if (singleLineComment != null &&
          i + singleLineComment.length <= len &&
          code.substring(i, i + singleLineComment.length) == singleLineComment) {
        flushBuffer();
        final lineEnd = code.indexOf('\n', i);
        final end = lineEnd == -1 ? len : lineEnd;
        tokens.add(HighlightToken(code.substring(i, end), colorComment));
        i = end;
        continue;
      }

      // 字符串（双引号、单引号、反引号）
      final ch = code[i];
      if (ch == '"' || ch == "'" || ch == '`') {
        flushBuffer();
        final quote = ch;
        // 处理三引号
        if (i + 2 < len && code[i + 1] == quote && code[i + 2] == quote) {
          final endIdx = code.indexOf('$quote$quote$quote', i + 3);
          final end = endIdx == -1 ? len : endIdx + 3;
          tokens.add(HighlightToken(code.substring(i, end), colorString));
          i = end;
        } else {
          var j = i + 1;
          while (j < len && code[j] != quote) {
            if (code[j] == '\\') j++; // 跳过转义
            j++;
          }
          if (j < len) j++; // 包含结束引号
          tokens.add(HighlightToken(code.substring(i, j), colorString));
          i = j;
        }
        continue;
      }

      // 数字
      if (_isDigit(ch) && (i == 0 || !_isIdentChar(code[i - 1]))) {
        flushBuffer();
        var j = i;
        while (j < len && (_isDigit(code[j]) || code[j] == '.' || code[j] == 'x' ||
            code[j] == 'X' || _isHexDigit(code[j]))) {
          j++;
        }
        // 后缀（如 0.5f, 100L）
        if (j < len && 'fFdDlL'.contains(code[j])) j++;
        tokens.add(HighlightToken(code.substring(i, j), colorNumber));
        i = j;
        continue;
      }

      // 标识符 / 关键字
      if (_isIdentStart(ch)) {
        flushBuffer();
        var j = i + 1;
        while (j < len && _isIdentChar(code[j])) {
          j++;
        }
        final word = code.substring(i, j);
        if (keywords.contains(word)) {
          tokens.add(HighlightToken(word, colorKeyword));
        } else if (types.contains(word) ||
            (word.isNotEmpty && word[0] == word[0].toUpperCase() && word[0] != word[0].toLowerCase())) {
          tokens.add(HighlightToken(word, colorType));
        } else {
          tokens.add(HighlightToken(word, null));
        }
        i = j;
        continue;
      }

      // 其他字符
      buf.write(ch);
      i++;
    }

    flushBuffer();
    return tokens;
  }

  static bool _isDigit(String ch) => ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57;
  static bool _isHexDigit(String ch) =>
      _isDigit(ch) ||
      (ch.codeUnitAt(0) >= 65 && ch.codeUnitAt(0) <= 70) ||
      (ch.codeUnitAt(0) >= 97 && ch.codeUnitAt(0) <= 102);
  static bool _isIdentStart(String ch) =>
      (ch.codeUnitAt(0) >= 65 && ch.codeUnitAt(0) <= 90) ||
      (ch.codeUnitAt(0) >= 97 && ch.codeUnitAt(0) <= 122) ||
      ch == '_' || ch == r'$';
  static bool _isIdentChar(String ch) => _isIdentStart(ch) || _isDigit(ch);

  static String? _getSingleLineComment(String lang) {
    switch (lang) {
      case 'python': case 'py': case 'ruby': case 'rb':
      case 'bash': case 'sh': case 'shell': case 'yaml': case 'yml':
        return '#';
      case 'sql':
        return '--';
      default:
        return '//';
    }
  }

  static List<String>? _getMultiLineComment(String lang) {
    switch (lang) {
      case 'python': case 'py':
        return null; // Python 用三引号，已在字符串处理中覆盖
      case 'html': case 'xml':
        return ['<!--', '-->'];
      default:
        return ['/*', '*/'];
    }
  }

  static Set<String> _getKeywords(String lang) {
    switch (lang) {
      case 'dart':
        return _dartKeywords;
      case 'java': case 'kotlin': case 'kt':
        return _javaKeywords;
      case 'javascript': case 'js': case 'typescript': case 'ts':
        return _jsKeywords;
      case 'python': case 'py':
        return _pythonKeywords;
      case 'c': case 'cpp': case 'c++': case 'h':
        return _cKeywords;
      case 'go': case 'golang':
        return _goKeywords;
      case 'rust': case 'rs':
        return _rustKeywords;
      case 'swift':
        return _swiftKeywords;
      case 'sql':
        return _sqlKeywords;
      case 'json':
        return <String>{}; // JSON 无关键字
      default:
        return _commonKeywords;
    }
  }

  static Set<String> _getTypes(String lang) {
    switch (lang) {
      case 'dart':
        return {'int', 'double', 'String', 'bool', 'num', 'List', 'Map', 'Set', 'Future', 'Stream', 'void', 'dynamic', 'var'};
      case 'java': case 'kotlin': case 'kt':
        return {'int', 'long', 'float', 'double', 'boolean', 'char', 'byte', 'short', 'void', 'String', 'Integer', 'Long', 'Float', 'Double'};
      case 'python': case 'py':
        return {'int', 'float', 'str', 'bool', 'list', 'dict', 'tuple', 'set', 'None', 'bytes'};
      case 'c': case 'cpp': case 'c++':
        return {'int', 'long', 'float', 'double', 'char', 'void', 'bool', 'size_t', 'string', 'vector', 'map'};
      default:
        return <String>{};
    }
  }

  static final _dartKeywords = <String>{
    'abstract', 'as', 'assert', 'async', 'await', 'break', 'case', 'catch',
    'class', 'const', 'continue', 'covariant', 'default', 'deferred', 'do',
    'else', 'enum', 'export', 'extends', 'extension', 'external', 'factory',
    'false', 'final', 'finally', 'for', 'get', 'if', 'implements', 'import',
    'in', 'interface', 'is', 'late', 'library', 'mixin', 'new', 'null', 'on',
    'operator', 'part', 'required', 'rethrow', 'return', 'sealed', 'set',
    'show', 'static', 'super', 'switch', 'sync', 'this', 'throw', 'true',
    'try', 'typedef', 'var', 'when', 'while', 'with', 'yield',
  };

  static final _javaKeywords = <String>{
    'abstract', 'assert', 'boolean', 'break', 'byte', 'case', 'catch', 'char',
    'class', 'const', 'continue', 'default', 'do', 'double', 'else', 'enum',
    'extends', 'false', 'final', 'finally', 'float', 'for', 'goto', 'if',
    'implements', 'import', 'instanceof', 'int', 'interface', 'long', 'native',
    'new', 'null', 'package', 'private', 'protected', 'public', 'return',
    'short', 'static', 'strictfp', 'super', 'switch', 'synchronized', 'this',
    'throw', 'throws', 'transient', 'true', 'try', 'void', 'volatile', 'while',
    'val', 'var', 'fun', 'when', 'object', 'data', 'sealed', 'override',
  };

  static final _jsKeywords = <String>{
    'async', 'await', 'break', 'case', 'catch', 'class', 'const', 'continue',
    'debugger', 'default', 'delete', 'do', 'else', 'export', 'extends',
    'false', 'finally', 'for', 'from', 'function', 'get', 'if', 'import',
    'in', 'instanceof', 'let', 'new', 'null', 'of', 'return', 'set', 'static',
    'super', 'switch', 'this', 'throw', 'true', 'try', 'typeof', 'undefined',
    'var', 'void', 'while', 'with', 'yield', 'type', 'interface', 'enum',
  };

  static final _pythonKeywords = <String>{
    'False', 'None', 'True', 'and', 'as', 'assert', 'async', 'await',
    'break', 'class', 'continue', 'def', 'del', 'elif', 'else', 'except',
    'finally', 'for', 'from', 'global', 'if', 'import', 'in', 'is',
    'lambda', 'nonlocal', 'not', 'or', 'pass', 'raise', 'return', 'try',
    'while', 'with', 'yield', 'self',
  };

  static final _cKeywords = <String>{
    'auto', 'break', 'case', 'char', 'const', 'continue', 'default', 'do',
    'double', 'else', 'enum', 'extern', 'float', 'for', 'goto', 'if',
    'inline', 'int', 'long', 'register', 'return', 'short', 'signed',
    'sizeof', 'static', 'struct', 'switch', 'typedef', 'union', 'unsigned',
    'void', 'volatile', 'while', 'class', 'namespace', 'template', 'typename',
    'public', 'private', 'protected', 'virtual', 'override', 'new', 'delete',
    'true', 'false', 'nullptr', 'this', 'throw', 'try', 'catch', 'using',
    '#include', '#define', '#ifdef', '#ifndef', '#endif', '#pragma',
  };

  static final _goKeywords = <String>{
    'break', 'case', 'chan', 'const', 'continue', 'default', 'defer', 'else',
    'fallthrough', 'for', 'func', 'go', 'goto', 'if', 'import', 'interface',
    'map', 'package', 'range', 'return', 'select', 'struct', 'switch', 'type',
    'var', 'true', 'false', 'nil',
  };

  static final _rustKeywords = <String>{
    'as', 'async', 'await', 'break', 'const', 'continue', 'crate', 'dyn',
    'else', 'enum', 'extern', 'false', 'fn', 'for', 'if', 'impl', 'in',
    'let', 'loop', 'match', 'mod', 'move', 'mut', 'pub', 'ref', 'return',
    'self', 'static', 'struct', 'super', 'trait', 'true', 'type', 'unsafe',
    'use', 'where', 'while',
  };

  static final _swiftKeywords = <String>{
    'break', 'case', 'catch', 'class', 'continue', 'default', 'defer', 'do',
    'else', 'enum', 'extension', 'fallthrough', 'false', 'for', 'func',
    'guard', 'if', 'import', 'in', 'init', 'let', 'nil', 'operator',
    'private', 'protocol', 'public', 'return', 'self', 'static', 'struct',
    'super', 'switch', 'throw', 'throws', 'true', 'try', 'typealias', 'var',
    'where', 'while',
  };

  static final _sqlKeywords = <String>{
    'SELECT', 'FROM', 'WHERE', 'INSERT', 'UPDATE', 'DELETE', 'CREATE',
    'ALTER', 'DROP', 'TABLE', 'INDEX', 'VIEW', 'INTO', 'VALUES', 'SET',
    'AND', 'OR', 'NOT', 'NULL', 'IS', 'IN', 'LIKE', 'BETWEEN', 'JOIN',
    'LEFT', 'RIGHT', 'INNER', 'OUTER', 'ON', 'AS', 'ORDER', 'BY', 'GROUP',
    'HAVING', 'LIMIT', 'OFFSET', 'UNION', 'ALL', 'DISTINCT', 'COUNT',
    'SUM', 'AVG', 'MAX', 'MIN', 'PRIMARY', 'KEY', 'FOREIGN', 'REFERENCES',
    'select', 'from', 'where', 'insert', 'update', 'delete', 'create',
    'alter', 'drop', 'table', 'index', 'into', 'values', 'set',
    'and', 'or', 'not', 'null', 'is', 'in', 'like', 'between', 'join',
    'left', 'right', 'inner', 'outer', 'on', 'as', 'order', 'by', 'group',
    'having', 'limit', 'offset', 'union', 'all', 'distinct',
  };

  static final _commonKeywords = <String>{
    'if', 'else', 'for', 'while', 'do', 'switch', 'case', 'break',
    'continue', 'return', 'class', 'function', 'true', 'false', 'null',
    'new', 'this', 'import', 'export', 'from', 'const', 'var', 'let',
    'try', 'catch', 'finally', 'throw', 'async', 'await',
  };
}

/// 高亮 Token
class HighlightToken {
  final String text;
  final int? color; // null = 默认颜色

  const HighlightToken(this.text, this.color);
}
