class WebBreakpoints {
  static const desktopMaxWidth = 1480.0;
  static const largeDesktop = 1280.0;
  static const desktop = 980.0;
  static const narrow = 760.0;
  static const compactWidth = desktop;

  static bool isLargeDesktop(double width) => width >= largeDesktop;
  static bool isDesktop(double width) => width >= desktop;
  static bool isNarrow(double width) => width >= narrow && width < desktop;
  static bool isSmall(double width) => width < narrow;

  static double gutter(double width) {
    if (width >= desktop) return 32;
    if (width >= narrow) return 24;
    return 16;
  }

  static double masterPaneWidth(double width) {
    if (width >= largeDesktop) return 420;
    return 380;
  }
}
