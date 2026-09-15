import 'dart:io';
import 'dart:typed_data';

Future<Uint8List?> readVacancyFileBytes(String path) =>
    File(path).readAsBytes();
