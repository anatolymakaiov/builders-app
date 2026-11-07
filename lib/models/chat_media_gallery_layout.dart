enum ChatMediaTileKind { portrait, landscape, other }

class ChatMediaGalleryLayout {
  const ChatMediaGalleryLayout._();

  static List<List<int>> rows(List<ChatMediaTileKind> kinds) {
    final rows = <List<int>>[];
    var portraitRow = <int>[];

    void flush() {
      if (portraitRow.isEmpty) return;
      rows.add(portraitRow);
      portraitRow = <int>[];
    }

    for (var index = 0; index < kinds.length; index++) {
      if (kinds[index] == ChatMediaTileKind.portrait) {
        portraitRow.add(index);
        if (portraitRow.length == 3) flush();
      } else {
        flush();
        rows.add([index]);
      }
    }
    flush();
    return rows;
  }
}
