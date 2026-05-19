import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'job_taxonomy_service.dart';

class ParsedVacancy {
  final String sourceFileName;
  final String jobDescription;
  final String responsibilities;
  final String requirements;
  final String requiredDocumentsAndCertifications;
  final String additionalInformation;
  final String? suggestedRole;

  const ParsedVacancy({
    required this.sourceFileName,
    this.jobDescription = "",
    this.responsibilities = "",
    this.requirements = "",
    this.requiredDocumentsAndCertifications = "",
    this.additionalInformation = "",
    this.suggestedRole,
  });

  bool get hasAnyParsedContent =>
      jobDescription.trim().isNotEmpty ||
      responsibilities.trim().isNotEmpty ||
      requirements.trim().isNotEmpty ||
      requiredDocumentsAndCertifications.trim().isNotEmpty ||
      additionalInformation.trim().isNotEmpty;

  ParsedVacancy copyWith({
    String? jobDescription,
    String? responsibilities,
    String? requirements,
    String? requiredDocumentsAndCertifications,
    String? additionalInformation,
  }) {
    return ParsedVacancy(
      sourceFileName: sourceFileName,
      jobDescription: jobDescription ?? this.jobDescription,
      responsibilities: responsibilities ?? this.responsibilities,
      requirements: requirements ?? this.requirements,
      requiredDocumentsAndCertifications: requiredDocumentsAndCertifications ??
          this.requiredDocumentsAndCertifications,
      additionalInformation:
          additionalInformation ?? this.additionalInformation,
      suggestedRole: suggestedRole,
    );
  }
}

class VacancyImportException implements Exception {
  final String message;

  const VacancyImportException(this.message);

  @override
  String toString() => message;
}

class VacancyImportService {
  const VacancyImportService._();

  static const supportedExtensions = {"pdf", "docx", "doc", "txt"};
  static const maxFileSizeBytes = 10 * 1024 * 1024;

  static Future<ParsedVacancy?> pickAndParseVacancyFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      type: FileType.custom,
      allowedExtensions: supportedExtensions.toList(),
    );
    if (result == null || result.files.isEmpty) return null;
    return parsePlatformFile(result.files.single);
  }

  static Future<ParsedVacancy> parsePlatformFile(PlatformFile file) async {
    final extension = file.extension?.toLowerCase().trim() ??
        file.name.split(".").last.toLowerCase().trim();
    if (!supportedExtensions.contains(extension)) {
      throw const VacancyImportException(
        "Unsupported file type. Please upload PDF, DOCX, DOC, or TXT.",
      );
    }
    if (file.size > maxFileSizeBytes) {
      throw const VacancyImportException(
        "File is too large. Please upload a vacancy file under 10 MB.",
      );
    }

    final bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null || bytes.isEmpty) {
      throw const VacancyImportException("Could not read selected file.");
    }

    final text = switch (extension) {
      "txt" => _extractTxt(bytes),
      "docx" => _extractDocx(bytes),
      "pdf" => _extractPdf(bytes),
      "doc" => _extractLegacyDoc(bytes),
      _ => "",
    };

    final cleanText = _normalizePlainText(text);
    if (cleanText.trim().isEmpty || !_hasReadableTextQuality(cleanText)) {
      throw const VacancyImportException(
        "Could not extract readable text. You can still create the vacancy manually.",
      );
    }

    return _parseSections(cleanText, file.name);
  }

  static String _extractTxt(Uint8List bytes) {
    return utf8.decode(bytes, allowMalformed: true);
  }

  static String _extractLegacyDoc(Uint8List bytes) {
    final text = latin1.decode(bytes, allowInvalid: true);
    final matches = RegExp(r'''[A-Za-z0-9£$€.,;:!?@#%&()/'"+\-\s]{5,}''')
        .allMatches(text)
        .map((match) => match.group(0) ?? "")
        .where((part) => RegExp(r"[A-Za-z]{3,}").hasMatch(part))
        .join("\n");
    return matches;
  }

  static String _extractDocx(Uint8List bytes) {
    final entries = _readZipEntries(bytes);
    final documentXml = entries["word/document.xml"];
    if (documentXml == null || documentXml.isEmpty) return "";

    var xml = utf8.decode(documentXml, allowMalformed: true);
    xml = xml
        .replaceAll(RegExp(r"<w:tab\s*/>"), "\t")
        .replaceAll(RegExp(r"</w:p>"), "\n")
        .replaceAll(RegExp(r"</w:tr>"), "\n")
        .replaceAll(RegExp(r"<[^>]+>"), " ");
    return _decodeXmlEntities(xml);
  }

  static Map<String, Uint8List> _readZipEntries(Uint8List bytes) {
    final entries = <String, Uint8List>{};

    void addEntry({
      required String name,
      required int method,
      required int compressedSize,
      required int dataStart,
    }) {
      final dataEnd = dataStart + compressedSize;
      if (dataStart < 0 || dataStart > bytes.length || dataEnd > bytes.length) {
        return;
      }

      final compressed = bytes.sublist(dataStart, dataEnd);
      try {
        if (method == 0) {
          entries[name] = Uint8List.fromList(compressed);
        } else if (method == 8) {
          entries[name] = Uint8List.fromList(zlib.decode(compressed));
        }
      } catch (_) {
        try {
          if (method == 8) {
            entries[name] = Uint8List.fromList(
              ZLibCodec(raw: true).decode(compressed),
            );
          }
        } catch (_) {
          // Skip corrupted or unsupported entries safely.
        }
      }
    }

    var centralOffset = 0;
    while (centralOffset + 46 < bytes.length) {
      if (_uint32(bytes, centralOffset) != 0x02014b50) {
        centralOffset++;
        continue;
      }

      final method = _uint16(bytes, centralOffset + 10);
      final compressedSize = _uint32(bytes, centralOffset + 20);
      final fileNameLength = _uint16(bytes, centralOffset + 28);
      final extraLength = _uint16(bytes, centralOffset + 30);
      final commentLength = _uint16(bytes, centralOffset + 32);
      final localHeaderOffset = _uint32(bytes, centralOffset + 42);
      final nameStart = centralOffset + 46;
      if (nameStart + fileNameLength > bytes.length ||
          localHeaderOffset + 30 > bytes.length) {
        break;
      }

      final name = utf8.decode(
        bytes.sublist(nameStart, nameStart + fileNameLength),
        allowMalformed: true,
      );
      final localNameLength = _uint16(bytes, localHeaderOffset + 26);
      final localExtraLength = _uint16(bytes, localHeaderOffset + 28);
      final dataStart =
          localHeaderOffset + 30 + localNameLength + localExtraLength;
      addEntry(
        name: name,
        method: method,
        compressedSize: compressedSize,
        dataStart: dataStart,
      );
      centralOffset = nameStart + fileNameLength + extraLength + commentLength;
    }

    if (entries.isNotEmpty) return entries;

    var offset = 0;
    while (offset + 30 < bytes.length) {
      if (_uint32(bytes, offset) != 0x04034b50) {
        offset++;
        continue;
      }

      final method = _uint16(bytes, offset + 8);
      final compressedSize = _uint32(bytes, offset + 18);
      final fileNameLength = _uint16(bytes, offset + 26);
      final extraLength = _uint16(bytes, offset + 28);
      final nameStart = offset + 30;
      final dataStart = nameStart + fileNameLength + extraLength;
      final dataEnd = dataStart + compressedSize;
      if (nameStart > bytes.length ||
          dataStart > bytes.length ||
          dataEnd > bytes.length) {
        break;
      }

      final name = utf8.decode(
        bytes.sublist(nameStart, nameStart + fileNameLength),
        allowMalformed: true,
      );
      addEntry(
        name: name,
        method: method,
        compressedSize: compressedSize,
        dataStart: dataStart,
      );

      offset = dataEnd;
    }
    return entries;
  }

  static int _uint16(Uint8List bytes, int offset) {
    return bytes[offset] | (bytes[offset + 1] << 8);
  }

  static int _uint32(Uint8List bytes, int offset) {
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }

  static String _extractPdf(Uint8List bytes) {
    final mappedText = _extractPdfWithToUnicode(bytes);
    if (_hasReadableTextQuality(mappedText)) return mappedText;

    final chunks = <String>[];
    final raw = latin1.decode(bytes, allowInvalid: true);
    chunks.addAll(_extractPdfTextObjects(raw));

    for (final streamMatch
        in RegExp(r"stream\r?\n([\s\S]*?)\r?\nendstream").allMatches(raw)) {
      final start = streamMatch.start;
      final header = raw.substring((start - 250).clamp(0, raw.length), start);
      if (!header.contains("/FlateDecode")) continue;
      final streamText = streamMatch.group(1);
      if (streamText == null || streamText.isEmpty) continue;
      try {
        final decoded = zlib.decode(latin1.encode(streamText));
        final decodedText = latin1.decode(decoded);
        chunks.addAll(_extractPdfTextObjects(decodedText));
        chunks.add(_extractReadableText(decodedText));
      } catch (_) {
        try {
          final decoded =
              ZLibCodec(raw: true).decode(latin1.encode(streamText));
          final decodedText = latin1.decode(decoded);
          chunks.addAll(_extractPdfTextObjects(decodedText));
          chunks.add(_extractReadableText(decodedText));
        } catch (_) {
          // Some PDF streams use predictors/encryption; leave them empty.
        }
      }
    }

    if (chunks.where((chunk) => chunk.trim().isNotEmpty).isEmpty) {
      chunks.add(_extractReadableText(raw));
    }

    final fallbackText = chunks.join("\n");
    return _hasReadableTextQuality(fallbackText) ? fallbackText : "";
  }

  static String _extractPdfWithToUnicode(Uint8List bytes) {
    final raw = latin1.decode(bytes, allowInvalid: true);
    final objects = _pdfObjects(raw);
    final decodedStreams = <String, String>{};

    String decodedStreamFor(String id) {
      return decodedStreams.putIfAbsent(id, () {
        final body = objects[id];
        if (body == null) return "";
        return _decodePdfStream(body);
      });
    }

    final fontObjectMaps = <String, Map<int, String>>{};
    objects.forEach((id, body) {
      final match = RegExp(r"/ToUnicode\s+(\d+)\s+0\s+R").firstMatch(body);
      if (match == null) return;
      final cmapObjectId = match.group(1);
      if (cmapObjectId == null) return;
      final cmap = _parseToUnicodeCMap(decodedStreamFor(cmapObjectId));
      if (cmap.isNotEmpty) fontObjectMaps[id] = cmap;
    });

    if (fontObjectMaps.isEmpty) return "";

    final fontResourceMaps = <String, Map<int, String>>{};
    for (final body in objects.values) {
      for (final fontBlock
          in RegExp(r"/Font\s*<<(.*?)>>", dotAll: true).allMatches(body)) {
        final block = fontBlock.group(1) ?? "";
        for (final fontMatch
            in RegExp(r"/(\w+)\s+(\d+)\s+0\s+R").allMatches(block)) {
          final resourceName = fontMatch.group(1);
          final fontObjectId = fontMatch.group(2);
          final cmap = fontObjectMaps[fontObjectId];
          if (resourceName != null && cmap != null) {
            fontResourceMaps[resourceName] = cmap;
          }
        }
      }
    }

    if (fontResourceMaps.isEmpty) return "";

    final chunks = <String>[];
    for (final entry in objects.entries) {
      final stream = decodedStreamFor(entry.key);
      if (!stream.contains("Tj") && !stream.contains("TJ")) continue;
      chunks.addAll(_extractPdfTextWithFontMaps(stream, fontResourceMaps));
    }

    final text = _shapePdfMappedText(chunks);
    return _hasReadableTextQuality(text) ? text : "";
  }

  static Map<String, String> _pdfObjects(String raw) {
    final objects = <String, String>{};
    for (final match
        in RegExp(r"(\d+)\s+0\s+obj([\s\S]*?)endobj").allMatches(raw)) {
      final id = match.group(1);
      final body = match.group(2);
      if (id != null && body != null) objects[id] = body;
    }
    return objects;
  }

  static String _decodePdfStream(String objectBody) {
    final match =
        RegExp(r"stream\r?\n([\s\S]*?)\r?\nendstream").firstMatch(objectBody);
    if (match == null) return "";
    final streamText = match.group(1);
    if (streamText == null) return "";
    final bytes = latin1.encode(streamText);
    if (!objectBody.contains("/FlateDecode")) {
      return latin1.decode(bytes, allowInvalid: true);
    }
    try {
      return latin1.decode(zlib.decode(bytes), allowInvalid: true);
    } catch (_) {
      try {
        return latin1.decode(
          ZLibCodec(raw: true).decode(bytes),
          allowInvalid: true,
        );
      } catch (_) {
        return "";
      }
    }
  }

  static Map<int, String> _parseToUnicodeCMap(String cmapText) {
    final map = <int, String>{};

    for (final match in RegExp(
      r"<([0-9A-Fa-f]{4})>\s+<([0-9A-Fa-f]{4,})>",
    ).allMatches(cmapText)) {
      final from = int.tryParse(match.group(1) ?? "", radix: 16);
      final to = _unicodeFromHex(match.group(2) ?? "");
      if (from != null && to.isNotEmpty) map[from] = to;
    }

    for (final match in RegExp(
      r"<([0-9A-Fa-f]{4})>\s+<([0-9A-Fa-f]{4})>\s+<([0-9A-Fa-f]{4,})>",
    ).allMatches(cmapText)) {
      final start = int.tryParse(match.group(1) ?? "", radix: 16);
      final end = int.tryParse(match.group(2) ?? "", radix: 16);
      final target = int.tryParse(match.group(3) ?? "", radix: 16);
      if (start == null || end == null || target == null || end < start) {
        continue;
      }
      for (var code = start; code <= end; code++) {
        map[code] = String.fromCharCode(target + code - start);
      }
    }

    return map;
  }

  static String _unicodeFromHex(String hex) {
    final clean = hex.replaceAll(RegExp(r"\s+"), "");
    if (clean.length < 4) return "";
    final units = <int>[];
    for (var i = 0; i + 3 < clean.length; i += 4) {
      final unit = int.tryParse(clean.substring(i, i + 4), radix: 16);
      if (unit != null) units.add(unit);
    }
    return String.fromCharCodes(units);
  }

  static List<String> _extractPdfTextWithFontMaps(
    String stream,
    Map<String, Map<int, String>> fontResourceMaps,
  ) {
    final chunks = <String>[];
    Map<int, String>? currentMap;
    final operatorPattern = RegExp(
      r"/(\w+)\s+[\d.]+\s+Tf|<([0-9A-Fa-f\s]+)>\s*Tj|\[((?:\s*(?:<[^>]+>|\([^)]*\))\s*-?\d*)+)\]\s*TJ|\((?:\\.|[^\\)])*\)\s*Tj",
    );

    for (final match in operatorPattern.allMatches(stream)) {
      final fontName = match.group(1);
      if (fontName != null) {
        currentMap = fontResourceMaps[fontName];
        continue;
      }

      if (currentMap == null) continue;

      final hexText = match.group(2);
      if (hexText != null) {
        chunks.add(_decodePdfCidHex(hexText, currentMap));
        continue;
      }

      final arrayText = match.group(3);
      if (arrayText != null) {
        final text = RegExp(r"<([0-9A-Fa-f\s]+)>")
            .allMatches(arrayText)
            .map((part) => _decodePdfCidHex(part.group(1) ?? "", currentMap!))
            .join("");
        chunks.add(text);
        continue;
      }

      final token = match.group(0) ?? "";
      if (token.startsWith("(")) {
        final end = token.lastIndexOf(")");
        if (end > 0) chunks.add(_decodePdfLiteral(token.substring(1, end)));
      }
    }

    return chunks.map(_cleanPdfMappedChunk).where((chunk) {
      return chunk.trim().isNotEmpty && RegExp(r"[A-Za-z0-9£]").hasMatch(chunk);
    }).toList();
  }

  static String _decodePdfCidHex(String hex, Map<int, String> cmap) {
    final clean = hex.replaceAll(RegExp(r"\s+"), "");
    final buffer = StringBuffer();
    for (var i = 0; i + 3 < clean.length; i += 4) {
      final code = int.tryParse(clean.substring(i, i + 4), radix: 16);
      if (code == null) continue;
      buffer.write(cmap[code] ?? "");
    }
    return buffer.toString();
  }

  static String _cleanPdfMappedChunk(String value) {
    return value
        .replaceAll("\$", " ")
        .replaceAll(RegExp(r"[\u000E\u000F]+"), " - ")
        .replaceAll(RegExp(r"[\u001D\u001F\u2580-\u259F]+"), ": ")
        .replaceAll("É", "£")
        .replaceAll("î", "£")
        .replaceAll("Ă", "£")
        .replaceAll("R e", "Re")
        .replaceAll("P ost", "Post")
        .replaceAll("T empor", "Tempor")
        .replaceAll(RegExp(r"\s+"), " ")
        .trim();
  }

  static String _shapePdfMappedText(List<String> chunks) {
    final cleaned = chunks
        .map(_cleanPdfMappedChunk)
        .where((chunk) => chunk.isNotEmpty)
        .toList();
    if (cleaned.isEmpty) return "";

    final lines = <String>[];
    final current = StringBuffer();

    void flush() {
      final line = _repairPdfLine(current.toString());
      if (line.isNotEmpty) lines.add(line);
      current.clear();
    }

    for (final chunk in cleaned) {
      final startsNewLine = _isPdfStandaloneHeading(chunk) ||
          RegExp(r"^[A-Z][A-Za-z /&-]{2,}:").hasMatch(chunk) ||
          RegExp(r"^[*•-]\s*").hasMatch(chunk);
      if (startsNewLine && current.isNotEmpty) flush();

      if (current.isEmpty) {
        current.write(chunk);
      } else if (_shouldJoinPdfChunks(current.toString(), chunk)) {
        current.write(chunk);
      } else {
        current.write(" $chunk");
      }

      if (_isPdfStandaloneHeading(chunk) ||
          chunk.endsWith(".") ||
          chunk.endsWith(":")) {
        flush();
      }
    }
    if (current.isNotEmpty) flush();

    final text = lines.join("\n");
    return _finalizePdfMappedText(_stripPdfJobBoardFooter(text)
        .replaceAllMapped(
          RegExp(r"\b(Job Title|Location|Requirements|Description)\s+"),
          (match) => "${match.group(1)}: ",
        )
        .replaceAllMapped(
          RegExp(
            r"\s+(Role & Responsibilities|Requirements|Job Details|How to Apply):",
          ),
          (match) => "\n${match.group(1)}:",
        )
        .replaceAll(RegExp(r"\n{3,}"), "\n\n")
        .trim());
  }

  static String _finalizePdfMappedText(String value) {
    return value
        .replaceAll(RegExp(r"\bW\s+We\b"), "We")
        .replaceAll(RegExp(r"\bWWe\b"), "We")
        .replaceAll(RegExp(r"\bR\s*Role\b"), "Role")
        .replaceAll(RegExp(r"\bV\s*Valid\b"), "Valid")
        .replaceAll(RegExp(r"\by\s*You\b"), "You")
        .replaceAll(RegExp(r"\bB\s+You\b"), "You")
        .replaceAll("safet y", "safety")
        .replaceAll("Abilit y", "Ability")
        .replaceAll("qualit y", "quality")
        .replaceAll("da y", "day")
        .replaceAll("Pa yment", "Payment")
        .replaceAll("Monda y", "Monday")
        .replaceAll("Frida y", "Friday")
        .replaceAll("opportunit y", "opportunity")
        .replaceAll("weekda y", "weekday")
        .replaceAll("punctualit y", "punctuality")
        .replaceAllMapped(
          RegExp(r"\b([A-Za-z])\s+y\b"),
          (match) => "${match.group(1)}y",
        )
        .replaceAllMapped(
          RegExp(r"\s+(Role & Responsibilities|Requirements):"),
          (match) => "\n${match.group(1)}:",
        )
        .replaceAllMapped(
          RegExp(r"\s+(JOB DUTIES|EXPERIENCE - QUALIFICATIONS|APPLY)\b"),
          (match) => "\n${match.group(1)}",
        )
        .replaceAll(RegExp(r"\n{3,}"), "\n\n")
        .trim();
  }

  static String _stripPdfJobBoardFooter(String value) {
    final marker = RegExp(
      r"\bJob Type\b|\bContract Length\b|\bContact Name\b|\bJob Reference\b|\bJob ID\b",
      caseSensitive: false,
    ).firstMatch(value);
    if (marker == null) return value;
    final head = value.substring(0, marker.start).trim();
    return head.isEmpty ? value : head;
  }

  static bool _isPdfStandaloneHeading(String value) {
    final normalized =
        value.toLowerCase().replaceAll(RegExp(r"[^a-z0-9 /&-]"), "").trim();
    return {
      "job description",
      "description",
      "about the role",
      "responsibilities",
      "duties",
      "main duties",
      "key responsibilities",
      "role responsibilities",
      "role and responsibilities",
      "role & responsibilities",
      "job duties",
      "requirements",
      "candidate requirements",
      "skills required",
      "experience required",
      "experience - qualifications",
      "required documents",
      "certifications",
      "cscs requirements",
      "licenses",
      "licences",
      "additional information",
      "other information",
    }.contains(normalized);
  }

  static bool _shouldJoinPdfChunks(String current, String next) {
    if (current.isEmpty || next.isEmpty) return false;
    final last = current[current.length - 1];
    final first = next[0];
    if (RegExp(r"[A-Za-z]").hasMatch(last) &&
        RegExp(r"[a-z]").hasMatch(first) &&
        next.length <= 4) {
      return true;
    }
    if (RegExp(r"[A-Za-z]").hasMatch(last) &&
        RegExp(r"[A-Za-z]").hasMatch(first) &&
        current.length <= 4) {
      return true;
    }
    return false;
  }

  static String _repairPdfLine(String value) {
    var line = value
        .replaceAll(RegExp(r"[\u2580-\u259F]+"), " ")
        .replaceAll(RegExp(r"\s+"), " ")
        .trim();
    if (line.isEmpty) return "";

    line = line
        .replaceAllMapped(
          RegExp(r"\b([A-Z])\s+([A-Z])([a-z])"),
          (match) {
            final first = match.group(1);
            final second = match.group(2);
            if (first == second) return "$second${match.group(3)}";
            return match.group(0) ?? "";
          },
        )
        .replaceAllMapped(
          RegExp(r"\b([A-Z])([A-Z])([a-z])"),
          (match) {
            final first = match.group(1);
            final second = match.group(2);
            if (first == second) return "$second${match.group(3)}";
            return match.group(0) ?? "";
          },
        )
        .replaceAllMapped(
          RegExp(r"\b([A-Za-z])\s+y\b"),
          (match) => "${match.group(1)}y",
        )
        .replaceAll("Tempor ary", "Temporary")
        .replaceAll("Agency/Emplo yer", "Agency/Employer")
        .replaceAll("libr ary", "library")
        .replaceAll("co .uk", "co.uk")
        .replaceAll("w as", "was")
        .replaceAll("e Are", "We Are")
        .replaceAll("e are", "We are")
        .replaceAll("vac ancy", "vacancy")
        .replaceAll("Employ er", "Employer")
        .replaceAll("Emploer", "Employer")
        .replaceAll("Exper ience", "Experience")
        .replaceAll("Qualifica tions", "Qualifications")
        .replaceAll("Job Title Dryliner", "Job Title: Dryliner")
        .replaceAll("Location Bristol", "Location: Bristol")
        .replaceAll("Require ments", "Requirements")
        .replaceAll("equirements", "Requirements")
        .replaceAll("RRequirements", "Requirements")
        .replaceAll("ole &", "Role &")
        .replaceAll("alid", "Valid")
        .replaceAll("y You", "You")
        .replaceAll("yYou", "You")
        .replaceAll("B You", "You")
        .replaceAll("y ou", "you")
        .replaceAll("ou ", "You ")
        .replaceAll("P osted", "Posted")
        .replaceAll("R equired", "Required")
        .replaceAll("R esponsibilities", "Responsibilities")
        .replaceAll("R ate", "Rate")
        .replaceAll("R eference", "Reference")
        .replaceAll("Contr act", "Contract")
        .replaceAll("sitedra wings", "site drawings")
        .replaceAll("dra wings", "drawings")
        .replaceAll("w alls", "walls")
        .replaceAll("fr ameworks", "frameworks")
        .replaceAll("Prov en", "Proven")
        .replaceAll("R eliable", "Reliable")
        .replaceAll("teamIf", "team. If")
        .replaceAll("av ailable", "available")
        .replaceAll("contr act", "contract")
        .replaceAll("dur ation", "duration")
        .replaceAll("P anels", "Panels")
        .replaceAll("work ed", "worked")
        .replaceAll("y ears", "years")
        .replaceAll("QU ALIFICA TIONS", "QUALIFICATIONS")
        .replaceAll("W ork", "Work")
        .replaceAll("P ermit", "Permit")
        .replaceAll("APPL Y", "APPLY")
        .replaceAll("T o apply", "To apply")
        .replaceAll("adv ert", "advert")
        .replaceAll("acop y", "a copy")
        .replaceAll("Responsibili ties", "Responsibilities")
        .replaceAll(RegExp(r"\b(\d+)\s*/\s*(\d{2}/\d{4})\b"), r"$1/$2");
    return line;
  }

  static List<String> _extractPdfTextObjects(String value) {
    final parts = <String>[];
    final literalString = RegExp(r"\((?:\\.|[^\\)])*\)\s*Tj");
    for (final match in literalString.allMatches(value)) {
      final token = match.group(0) ?? "";
      parts.add(_decodePdfLiteral(token.substring(1, token.lastIndexOf(")"))));
    }

    final hexString = RegExp(r"<([0-9A-Fa-f\s]{4,})>\s*Tj");
    for (final match in hexString.allMatches(value)) {
      parts.add(_decodePdfHex(match.group(1) ?? ""));
    }

    final arrayString = RegExp(
        r"\[((?:\s*(?:\((?:\\.|[^\\)])*\)|<[0-9A-Fa-f\s]+>)\s*-?\d*)+)\]\s*TJ");
    for (final match in arrayString.allMatches(value)) {
      final token = match.group(1) ?? "";
      final text = RegExp(r"\((?:\\.|[^\\)])*\)|<[0-9A-Fa-f\s]+>")
          .allMatches(token)
          .map((part) {
        final raw = part.group(0) ?? "";
        if (raw.startsWith("<")) {
          return _decodePdfHex(raw.substring(1, raw.length - 1));
        }
        return _decodePdfLiteral(raw.substring(1, raw.length - 1));
      }).join("");
      parts.add(text);
    }

    final looseLiteral = RegExp(r"\((?:\\.|[^\\)]){4,}\)");
    for (final match in looseLiteral.allMatches(value)) {
      final token = match.group(0) ?? "";
      final decoded = _decodePdfLiteral(token.substring(1, token.length - 1));
      if (RegExp(r"[A-Za-z]{3,}").hasMatch(decoded)) parts.add(decoded);
    }

    return parts;
  }

  static String _decodePdfHex(String value) {
    final clean = value.replaceAll(RegExp(r"\s+"), "");
    if (clean.length < 2) return "";
    final hex = clean.length.isOdd ? "${clean}0" : clean;
    final bytes = <int>[];
    for (var i = 0; i + 1 < hex.length; i += 2) {
      final byte = int.tryParse(hex.substring(i, i + 2), radix: 16);
      if (byte != null) bytes.add(byte);
    }
    if (bytes.isEmpty) return "";

    final hasUtf16Pattern = bytes.length > 3 &&
        bytes.where((byte) => byte == 0).length > bytes.length / 4;
    if (hasUtf16Pattern ||
        (bytes.length > 1 && bytes.first == 0xfe && bytes[1] == 0xff)) {
      final start =
          bytes.length > 1 && bytes.first == 0xfe && bytes[1] == 0xff ? 2 : 0;
      final codeUnits = <int>[];
      for (var i = start; i + 1 < bytes.length; i += 2) {
        codeUnits.add((bytes[i] << 8) | bytes[i + 1]);
      }
      return String.fromCharCodes(codeUnits);
    }

    return utf8.decode(bytes, allowMalformed: true);
  }

  static String _extractReadableText(String value) {
    return RegExp(r'''[A-Za-z0-9£$€.,;:!?@#%&()/'"+\-\s]{5,}''')
        .allMatches(value)
        .map((match) => match.group(0) ?? "")
        .map((part) => part.replaceAll(RegExp(r"\s+"), " ").trim())
        .where((part) => RegExp(r"[A-Za-z]{3,}").hasMatch(part))
        .join("\n");
  }

  static bool _hasReadableTextQuality(String value) {
    final text = value.trim();
    if (text.length < 24) return false;
    final letters = RegExp(r"[A-Za-z]").allMatches(text).length;
    final controls =
        RegExp(r"[\u0000-\u0008\u000B-\u001F\u007F]").allMatches(text).length;
    final replacement =
        RegExp(r"[\uFFFD\u2580-\u259F]").allMatches(text).length;
    if (letters < 12) return false;
    if (controls > text.length * 0.03) return false;
    if (replacement > text.length * 0.03) return false;
    return letters / text.length > 0.25;
  }

  static String _decodePdfLiteral(String value) {
    return value
        .replaceAll(r"\(", "(")
        .replaceAll(r"\)", ")")
        .replaceAll(r"\\", r"\")
        .replaceAll(r"\n", "\n")
        .replaceAll(r"\r", "\n")
        .replaceAll(r"\t", "\t");
  }

  static ParsedVacancy _parseSections(String text, String fileName) {
    final lines = text
        .split("\n")
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final buckets = <String, List<String>>{
      "jobDescription": [],
      "responsibilities": [],
      "requirements": [],
      "requiredDocumentsAndCertifications": [],
      "additionalInformation": [],
    };
    var current = "additionalInformation";

    for (final line in lines) {
      final heading = _headingFor(line);
      if (heading != null) {
        current = heading;
        final remainder = _removeHeading(line);
        if (remainder.isNotEmpty) buckets[current]!.add(remainder);
        continue;
      }
      if (current == "additionalInformation" && _isJobBoardBoilerplate(line)) {
        continue;
      }
      buckets[current]!.add(line);
    }

    return ParsedVacancy(
      sourceFileName: fileName,
      jobDescription: _joinBucket(buckets["jobDescription"]!),
      responsibilities: _joinBucket(buckets["responsibilities"]!),
      requirements: _joinBucket(buckets["requirements"]!),
      requiredDocumentsAndCertifications:
          _joinBucket(buckets["requiredDocumentsAndCertifications"]!),
      additionalInformation: _joinBucket(buckets["additionalInformation"]!),
      suggestedRole: _detectRoleSuggestion(text),
    );
  }

  static String? _headingFor(String line) {
    final normalized =
        line.toLowerCase().replaceAll(RegExp(r"[^a-z0-9 /&-]"), "").trim();
    final headingOnly = normalized.split(RegExp(r"[:\\-]")).first.trim();

    bool isOneOf(Iterable<String> values) => values.any((value) {
          return headingOnly == value ||
              normalized == value ||
              normalized.startsWith("$value ") ||
              normalized.startsWith("$value:") ||
              normalized.startsWith("$value -");
        });

    if (isOneOf(["job description", "description", "about the role"])) {
      return "jobDescription";
    }
    if (isOneOf([
      "responsibilities",
      "duties",
      "main duties",
      "key responsibilities",
      "role responsibilities",
      "role and responsibilities",
      "role & responsibilities",
      "job duties",
    ])) {
      return "responsibilities";
    }
    if (isOneOf([
      "requirements",
      "candidate requirements",
      "skills required",
      "experience required",
      "experience - qualifications",
    ])) {
      return "requirements";
    }
    if (isOneOf([
      "required documents",
      "certifications",
      "cscs requirements",
      "licenses",
      "licences",
    ])) {
      return "requiredDocumentsAndCertifications";
    }
    if (isOneOf([
      "additional information",
      "other information",
      "job details",
      "how to apply",
      "apply",
    ])) {
      return "additionalInformation";
    }
    return null;
  }

  static String _removeHeading(String line) {
    final index = line.indexOf(RegExp(r"[:\\-]"));
    if (index < 0 || index + 1 >= line.length) return "";
    return line.substring(index + 1).trim();
  }

  static bool _isJobBoardBoilerplate(String line) {
    final lower = line.toLowerCase();
    return lower.contains("cv-library") ||
        lower.contains("cv library") ||
        lower.contains("job url") ||
        lower.contains("print job") ||
        lower.contains("salary/rate") ||
        lower.startsWith("-library") ||
        lower.startsWith("this job was found on");
  }

  static String? _detectRoleSuggestion(String text) {
    final roles = JobTaxonomyService.suggestions(text, limit: 1);
    if (roles.isEmpty) return null;
    return roles.first.canonical;
  }

  static String _joinBucket(List<String> lines) {
    return lines.join("\n").trim();
  }

  static String _normalizePlainText(String value) {
    return _decodeXmlEntities(value)
        .replaceAll("\u0000", " ")
        .replaceAll("\$", " ")
        .replaceAll(RegExp(r"[\u000E\u000F]+"), " - ")
        .replaceAll(RegExp(r"[\u001D\u001F\u2580-\u259F]+"), ": ")
        .replaceAll(RegExp(r"[ \t]+"), " ")
        .replaceAll(RegExp(r"\n{3,}"), "\n\n")
        .trim();
  }

  static String _decodeXmlEntities(String value) {
    return value
        .replaceAll("&amp;", "&")
        .replaceAll("&lt;", "<")
        .replaceAll("&gt;", ">")
        .replaceAll("&quot;", '"')
        .replaceAll("&apos;", "'")
        .replaceAllMapped(RegExp(r"&#(\d+);"), (match) {
      final code = int.tryParse(match.group(1) ?? "");
      if (code == null) return match.group(0) ?? "";
      return String.fromCharCode(code);
    });
  }
}
