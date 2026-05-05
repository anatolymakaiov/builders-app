import 'package:cloud_firestore/cloud_firestore.dart';

class Job {
  final String id;

  final String title;
  final String trade;
  final String site;

  final String location;
  final String street;
  final String city;
  final String postcode;
  final String county;

  final double rate;

  final double lat;
  final double lng;

  final String description;
  final String candidateRequirements;
  final String requiredDocuments;

  final String companyName;
  final String? companyLogo;

  final List<String> photos;

  /// hourly / price / negotiable
  final String jobType;

  final String duration;
  final String weeklyHours;
  final DateTime? startDate;
  final String employmentType;

  /// 🔥 FIX: теперь НЕ nullable
  final String ownerId;

  final int applicantsCount;
  final DateTime? createdAt;
  final String status;
  final String moderationStatus;
  final String moderationReason;

  /// 🔥 NEW (КРИТИЧНО ДЛЯ БРИГАД)
  final int positions;
  final int filledPositions;

  Job({
    required this.id,
    required this.title,
    required this.trade,
    required this.site,
    required this.location,
    required this.street,
    required this.city,
    required this.postcode,
    this.county = "",
    required this.rate,
    required this.lat,
    required this.lng,
    required this.description,
    this.candidateRequirements = "",
    this.requiredDocuments = "",
    required this.companyName,
    this.companyLogo,
    required this.photos,
    required this.jobType,
    required this.duration,
    this.weeklyHours = "",
    this.startDate,
    required this.employmentType,
    required this.ownerId,
    this.applicantsCount = 0,
    this.createdAt,
    this.status = "active",
    this.moderationStatus = "",
    this.moderationReason = "",

    /// 🔥 NEW
    this.positions = 1,
    this.filledPositions = 0,
  });

  /// 🔥 PAYMENT TEXT
  String get rateText {
    if (jobType == "negotiable") {
      return "Price negotiable";
    }

    if (jobType == "price") {
      return "£${rate.toInt()} project";
    }

    return "£${rate.toInt()}/hour";
  }

  String get workFormatText {
    if (jobType == "price") return "Price";
    if (jobType == "negotiable") return "Negotiable";
    return "Daywork";
  }

  String get listRateText {
    if (jobType != "hourly" || rate <= 0) return "";
    return "£${rate.toInt()}/hour";
  }

  String get displayTitle {
    final cleanTitle = title.trim();
    if (cleanTitle.isNotEmpty) return cleanTitle;
    return trade.trim();
  }

  bool get shouldShowTrade {
    final cleanTrade = trade.trim();
    if (cleanTrade.isEmpty) return false;
    return cleanTrade.toLowerCase() != displayTitle.toLowerCase();
  }

  /// 🔥 SHORT META
  String get shortMeta {
    final parts = <String>[];

    parts.add(rateText);

    if (duration.isNotEmpty) {
      parts.add(duration);
    }

    if (startDate != null) {
      parts.add("Start ${_formatDate(startDate!)}");
    }

    /// 🔥 показываем если больше 1
    if (positions > 1) {
      parts.add("$positions workers needed");
    }

    return parts.join(" • ");
  }

  /// 🔥 СКОЛЬКО ОСТАЛОСЬ МЕСТ
  int get remainingPositions =>
      (positions - filledPositions).clamp(0, positions);

  bool get isClosed => status == "completed" || status == "closed";

  bool get isApproved => moderationStatus == "approved";

  String get moderationLabel {
    switch (moderationStatus) {
      case "pending_review":
        return "Pending review";
      case "approved":
        return "Approved";
      case "rejected":
        return "Rejected";
      default:
        return "Not reviewed";
    }
  }

  /// 🔥 ADDRESS
  String get fullAddress {
    return [
      street.trim(),
      city.trim(),
      postcode.trim(),
    ].where((part) => part.isNotEmpty).join(", ");
  }

  String _formatDate(DateTime date) {
    return "${date.day}/${date.month}";
  }

  /// 🔥 FACTORY
  factory Job.fromFirestore(String id, Map<String, dynamic> data) {
    double safeDouble(dynamic value) {
      if (value == null) return 0;

      if (value is int) return value.toDouble();
      if (value is double) return value;

      if (value is String) {
        return double.tryParse(value) ?? 0;
      }

      return 0;
    }

    List<String> safePhotos(dynamic value) {
      if (value is List) {
        return value.map((e) => e.toString()).toList();
      }
      return [];
    }

    DateTime? safeDate(dynamic value) {
      if (value is Timestamp) {
        return value.toDate();
      }
      return null;
    }

    int safeInt(dynamic value) {
      if (value == null) return 0;

      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) return int.tryParse(value.trim()) ?? 0;

      return 0;
    }

    /// 🔥 ВАЖНО: вычисляем ДО return
    final positionsRaw = safeInt(data["positions"]);
    final ownerId = (data["ownerId"] ??
            data["employerId"] ??
            data["createdBy"] ??
            data["userId"] ??
            "unknown")
        .toString();

    return Job(
      id: id,

      title: data["title"] ?? "",
      trade: data["trade"] ?? "",
      site: data["site"] ?? "",

      location: data["location"] ?? "",
      street: data["street"] ?? "",
      city: data["city"] ?? "",
      postcode: data["postcode"] ?? "",
      county: (data["county"] ?? data["siteCounty"] ?? "").toString(),

      rate: safeDouble(data["rate"]),

      lat: safeDouble(data["lat"]),
      lng: safeDouble(data["lng"]),

      description: data["description"] ?? "",
      candidateRequirements: data["candidateRequirements"]?.toString() ?? "",
      requiredDocuments: data["requiredDocuments"]?.toString() ?? "",

      companyName: data["companyName"] ?? "",
      companyLogo: data["companyLogo"],

      photos: safePhotos(data["photos"]),

      jobType: data["jobType"] ?? "hourly",

      duration: data["duration"] ?? "",
      weeklyHours: data["weeklyHours"]?.toString() ?? "",
      startDate: safeDate(data["startDate"]),
      employmentType: data["employmentType"] ?? "",

      ownerId: ownerId,

      applicantsCount: safeInt(data["applicantsCount"]),
      createdAt: safeDate(data["createdAt"]),
      status: data["status"]?.toString() ?? "active",
      moderationStatus: data["moderationStatus"]?.toString() ?? "",
      moderationReason: data["moderationReason"]?.toString() ?? "",

      /// 🔥 FIX
      positions: positionsRaw == 0 ? 1 : positionsRaw,
      filledPositions: safeInt(data["filledPositions"]),
    );
  }
}
