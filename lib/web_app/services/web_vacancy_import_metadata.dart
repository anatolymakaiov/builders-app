import '../../services/vacancy_import_service.dart';

class WebVacancyImportMetadata {
  const WebVacancyImportMetadata({
    this.site = '',
    this.duration = '',
    this.weeklyHours = '',
    this.positions,
    this.rate,
    this.postcode = '',
    this.addressLine1 = '',
    this.city = '',
  });

  final String site;
  final String duration;
  final String weeklyHours;
  final int? positions;
  final double? rate;
  final String postcode;
  final String addressLine1;
  final String city;

  factory WebVacancyImportMetadata.fromParsed(ParsedVacancy parsed) {
    final text = [
      parsed.jobDescription,
      parsed.responsibilities,
      parsed.requirements,
      parsed.requiredDocumentsAndCertifications,
      parsed.additionalInformation,
    ].where((value) => value.trim().isNotEmpty).join('\n');

    final rateMatch = RegExp(
      r'(?:£\s*)?(\d+(?:[.,]\d{1,2})?)\s*(?:per\s*(?:hour|hr)|/\s*(?:hour|hr)|p/?h\b)',
      caseSensitive: false,
    ).firstMatch(text);
    final positionsText = _lineValue(text, const [
          'workers needed',
          'number of workers',
          'positions',
          'vacancies',
        ]) ??
        RegExp(
          r'\b(?:need|required|seeking)\s+(\d+)\s+(?:workers?|people|operatives?)\b',
          caseSensitive: false,
        ).firstMatch(text)?.group(1);
    final hoursText = _lineValue(text, const [
          'hours per week',
          'weekly hours',
          'working hours',
        ]) ??
        RegExp(
          r'\b(\d+(?:[.,]\d+)?)\s*(?:hours|hrs)\s*(?:per|a|/)\s*week\b',
          caseSensitive: false,
        ).firstMatch(text)?.group(1);
    final postcodeMatch = RegExp(
      r'\b([A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2})\b',
      caseSensitive: false,
    ).firstMatch(text);
    final postcode = _normalizePostcode(postcodeMatch?.group(1) ?? '');
    var address = _lineValue(text, const [
          'site address',
          'work address',
          'address',
        ]) ??
        '';
    if (postcode.isNotEmpty) {
      address = address
          .replaceAll(RegExp(RegExp.escape(postcode), caseSensitive: false), '')
          .replaceAll(RegExp(r'[,\s]+$'), '')
          .trim();
    }

    return WebVacancyImportMetadata(
      site: _lineValue(text, const [
            'site',
            'site name',
            'project',
            'project name',
          ]) ??
          '',
      duration: _lineValue(text, const [
            'duration',
            'contract length',
            'work period',
          ]) ??
          '',
      weeklyHours: hoursText?.trim() ?? '',
      positions: int.tryParse(positionsText?.trim() ?? ''),
      rate: double.tryParse(
        (rateMatch?.group(1) ?? '').replaceAll(',', '.'),
      ),
      postcode: postcode,
      addressLine1: address,
      city: _lineValue(text, const ['town / city', 'town', 'city']) ?? '',
    );
  }

  static String? _lineValue(String text, List<String> labels) {
    final labelPattern = labels.map(RegExp.escape).join('|');
    return RegExp(
      '^(?:$labelPattern)\\s*[:\\-]\\s*(.+)\$',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(text)?.group(1)?.trim();
  }

  static String _normalizePostcode(String value) {
    final compact = value.toUpperCase().replaceAll(RegExp(r'\s+'), '');
    if (compact.length <= 3) return compact;
    return '${compact.substring(0, compact.length - 3)} '
        '${compact.substring(compact.length - 3)}';
  }
}
