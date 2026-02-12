# Markdown 渲染完整测试文档

本文档覆盖 NBreader Markdown 渲染引擎的所有标签与边界情况。

## 二级标题

### 三级标题

#### 四级标题

##### 五级标题

###### 六级标题

---

## 文本样式

这是一段普通文本。支持**加粗**、*斜体*、~~删除线~~、`行内代码 inline_code()`，以及***加粗斜体***组合样式。

还支持<mark>高亮文本 Highlight</mark>、<u>下划线文本 Underline</u>、H<sub>2</sub>O 化学式下标、E=mc<sup>2</sup> 上标，以及<kbd>Ctrl</kbd>+<kbd>C</kbd> 键盘快捷键样式。

多种样式组合：**加粗内含`行内代码`和*斜体*混排**，~~删除线内含**加粗**~~。

<!-- 这是 HTML 注释，不应该被渲染 -->

<!-- 
  多行注释
  也不应该渲染
-->

## 链接

这是一个[百度链接](https://www.baidu.com)，这是一个[带标题的链接](https://www.google.com "Google首页")。文中嵌入[链接](https://example.com)测试。

## 分割线

上面是文本，下面是三种分割线：

---

***

___

分割线之后的内容。

## 代码块

行内代码：`print("Hello World")`，另一个较长的：`Map<String, List<int>> complexGenericType = {};`

下面是一个 Dart 代码块（含长行测试溢出裁剪）：

```dart
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// 这是一个非常长的注释行，用于测试代码块在单行超出边界时的裁剪行为，确保文字不会溢出背景矩形区域。This is a very long comment line to test code block clipping behavior.
class MyHomePage extends StatefulWidget {
  final String title;
  final Map<String, List<Map<String, dynamic>>> complexNestedGenericParameter;

  const MyHomePage({super.key, required this.title, required this.complexNestedGenericParameter});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('You have pushed the button this many times:'),
            Text('$_counter', style: Theme.of(context).textTheme.headlineMedium),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
```

下面是一个 JSON 代码块：

```json
{
  "name": "NBreader",
  "version": "1.0.0",
  "description": "Flutter 电子书阅读器，支持 TXT/EPUB/Markdown 格式",
  "features": ["TXT解析", "EPUB解析", "Markdown渲染", "页面动画", "夜间模式"],
  "author": {
    "name": "开发者",
    "email": "dev@example.com"
  },
  "dependencies": {
    "flutter": ">=3.0.0",
    "markdown": "^7.2.2",
    "path_provider": "^2.1.0"
  }
}
```

下面是一个 Python 代码块：

```python
def fibonacci(n: int) -> list[int]:
    """生成斐波那契数列，这是一个相当长的函数文档字符串，用于测试代码块的长行溢出裁剪"""
    if n <= 0:
        return []
    sequence = [0, 1]
    while len(sequence) < n:
        sequence.append(sequence[-1] + sequence[-2])
    return sequence[:n]

# 调用示例
result = fibonacci(20)
print(f"斐波那契数列前20项: {result}")
```

下面是一个无语言标识的代码块：

```
这是纯文本代码块
没有语法高亮
用于展示预格式化文本，例如命令输出：
  total 128
  drwxr-xr-x  12 user  staff   384 Jan  1 12:00 .
  -rw-r--r--   1 user  staff  2048 Jan  1 12:00 README.md
```

## 引用块

> 这是一个引用块。引用块可以包含**加粗**和*斜体*文本。
>
> 引用块可以有多段内容。这是第二段。

> 嵌套引用：
>
> > 这是嵌套的引用内容。嵌套引用的深度可以更深。
> >
> > > 三层嵌套引用。

> 引用内的代码：`console.log("hello")` 和链接 [点击这里](https://example.com)

## 列表

### 无序列表

- 第一项
- 第二项
  - 嵌套第一项
  - 嵌套第二项
    - 深层嵌套项 A
    - 深层嵌套项 B
- 第三项：包含**加粗**和`代码`

### 有序列表

1. 第一步：安装 Flutter SDK
2. 第二步：创建项目 `flutter create myapp`
3. 第三步：运行应用
   1. 子步骤 A：连接设备
   2. 子步骤 B：执行 `flutter run`
4. 第四步：发布

### 任务列表

- [x] 已完成：TXT 解析引擎
- [x] 已完成：EPUB 解析引擎
- [x] 已完成：页面翻转动画
- [ ] 进行中：Markdown 渲染
- [ ] 待办：PDF 支持
- [ ] 待办：全文搜索优化

## 表格

| 功能模块 | 状态 | 优先级 | 说明 |
|---------|:----:|:-----:|------|
| TXT 解析 | ✅ | P0 | 支持自动编码检测 |
| EPUB 解析 | ✅ | P0 | 支持 OPF/NCX/XHTML |
| Markdown | 🚧 | P1 | 代码块/表格/引用块 |
| 页面动画 | ✅ | P1 | 五种动画效果 |
| 夜间模式 | ✅ | P2 | 自动/手动切换 |
| PDF 支持 | ❌ | P3 | 暂不支持 |

## 图片

网络图片测试：

![测试图片](https://via.placeholder.com/300x200/4CAF50/FFFFFF?text=NBreader)

## 复合嵌套测试

下面测试多种元素的复杂组合：

1. **加粗列表项**包含`行内代码`和<mark>高亮</mark>
2. *斜体列表项*包含[链接](https://example.com)和<u>下划线</u>
3. ~~删除线列表项~~包含<kbd>Enter</kbd>按键

> 引用块内的复杂内容：
>
> - 引用内**加粗**列表项
> - 引用内`代码`列表项
>
> 引用内包含<mark>高亮文本</mark>和<kbd>Shift</kbd>+<kbd>Tab</kbd>快捷键。

---

**以上是完整的 Markdown 渲染测试。** 如果所有元素都正确显示——包括<mark>高亮</mark>、<u>下划线</u>、<sub>下标</sub>、<sup>上标</sup>、<kbd>按键</kbd>——则说明渲染引擎工作正常。
