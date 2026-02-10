/// 页面类型
enum PageType {
  previous,
  current,
  next;

  PageType getNext() {
    switch (this) {
      case PageType.previous:
        return PageType.current;
      case PageType.current:
        return PageType.next;
      case PageType.next:
        return PageType.next; // 已经是最后
    }
  }

  PageType getPrevious() {
    switch (this) {
      case PageType.previous:
        return PageType.previous; // 已经是最前
      case PageType.current:
        return PageType.previous;
      case PageType.next:
        return PageType.current;
    }
  }
}

/// 翻页动画类型
enum PageAnimType {
  none,
  cover,
  slide,
  simulation,
  scroll,
}
