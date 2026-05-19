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
    if (cleanText.trim().isEmpty) {
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
      final compressed = bytes.sublist(dataStart, dataEnd);
      try {
        if (method == 0) {
          entries[name] = Uint8List.fromList(compressed);
        } else if (method == 8) {
          entries[name] = Uint8List.fromList(
            ZLibCodec(raw: true).decode(compressed),
          );
        }
      } catch (_) {
        // Skip corrupted or unsupported entries safely.
      }

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
        chunks.addAll(_extractPdfTextObjects(latin1.decode(decoded)));
      } catch (_) {
        // Some PDF streams use predictors/encryption; leave them empty.
      }
    }

    return chunks.join("\n");
  }

  static List<String> _extractPdfTextObjects(String value) {
    final parts = <String>[];
    final literalString = RegExp(r"\((?:\\.|[^\\)])*\)\s*Tj");
    for (final match in literalString.allMatches(value)) {
      final token = match.group(0) ?? "";
      parts.add(_decodePdfLiteral(token.substring(1, token.lastIndexOf(")"))));
    }

    final arrayString =
        RegExp(r"\[((?:\s*\((?:\\.|[^\\)])*\)\s*-?\d*)+)\]\s*TJ");
    for (final match in arrayString.allMatches(value)) {
      final token = match.group(1) ?? "";
      final text = RegExp(r"\((?:\\.|[^\\)])*\)").allMatches(token).map((part) {
        final raw = part.group(0) ?? "()";
        return _decodePdfLiteral(raw.substring(1, raw.length - 1));
      }).join("");
      parts.add(text);
    }

    return parts;
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

    bool isOneOf(Iterable<String> values) => values.any((value) =>
        headingOnly == value ||
        normalized == value ||
        normalized.startsWith("$value:") ||
        normalized.startsWith("$value -"));

    if (isOneOf(["job description", "description", "about the role"])) {
      return "jobDescription";
    }
    if (isOneOf([
      "responsibilities",
      "duties",
      "main duties",
      "key responsibilities",
    ])) {
      return "responsibilities";
    }
    if (isOneOf([
      "requirements",
      "candidate requirements",
      "skills required",
      "experience required",
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
    if (isOneOf(["additional information", "other information"])) {
      return "additionalInformation";
    }
    return null;
  }

  static String _removeHeading(String line) {
    final index = line.indexOf(RegExp(r"[:\\-]"));
    if (index < 0 || index + 1 >= line.length) return "";
    return line.substring(index + 1).trim();
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
