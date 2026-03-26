import 'package:cloud_firestore/cloud_firestore.dart';

class Job {
  final String id;

  final String title;
  final String trade;

  final String location;
  final String street;
  final String city;
  final String postcode;

  final double rate;

  final double lat;
  final double lng;

  final String? description;

  final String? companyName;
  final String? companyLogo;

  final List<String>? photos;

  /// hourly / price / negotiable
  final String? jobType;

  /// NEW: duration (e.g. "2 weeks", "3 months")
  final String? duration;

  /// NEW: start date
  final DateTime? startDate;

  /// NEW: CIS / self-employed
  final String? employmentType;

  final String? ownerId;

  final int applicantsCount;

  final DateTime? createdAt;

  Job({
    required this.id,
    required this.title,
    required this.trade,

    required this.location,
    required this.street,
    required this.city,
    required this.postcode,

    required this.rate,

    required this.lat,
    required this.lng,

    this.description,

    this.companyName,
    this.companyLogo,

    this.photos,

    this.jobType,

    this.duration,
    this.startDate,
    this.employmentType,

    this.ownerId,

    this.applicantsCount = 0,

    this.createdAt,
  });

  /// PAYMENT TEXT
  String get rateText {
    if (jobType == "negotiable") {
      return "Price negotiable";
    }

    if (jobType == "price") {
      return "£${rate.toInt()} project";
    }

    return "£${rate.toInt()}/hour";
  }

  /// IS PRICE WORK
  bool get isPriceWork {
    return jobType == "price" || jobType == "negotiable";
  }

  /// FULL ADDRESS
  String get fullAddress {
    return "$street, $city $postcode";
  }

  /// NEW: SHORT META (для карточек)
  String get shortMeta {
    final parts = <String>[];

    parts.add(rateText);

    if (duration != null && duration!.isNotEmpty) {
      parts.add(duration!);
    }

    if (startDate != null) {
      parts.add("Start ${_formatDate(startDate!)}");
    }

    return parts.join(" • ");
  }

  String _formatDate(DateTime date) {
    return "${date.day}/${date.month}";
  }

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

    List<String>? safePhotos(dynamic value) {
      if (value == null) return null;

      if (value is List) {
        return value.map((e) => e.toString()).toList();
      }

      return null;
    }

    DateTime? safeDate(dynamic value) {
      if (value == null) return null;

      if (value is Timestamp) {
        return value.toDate();
      }

      return null;
    }

    int safeInt(dynamic value) {
      if (value == null) return 0;

      if (value is int) return value;

      if (value is double) return value.toInt();

      return 0;
    }

    return Job(
      id: id,

      title: data["title"] ?? "",

      trade: data["trade"] ?? data["title"] ?? "",

      location: data["location"] ?? "",

      street: data["street"] ?? "",

      city: data["city"] ?? "",

      postcode: data["postcode"] ?? "",

      rate: safeDouble(data["rate"]),

      lat: safeDouble(data["lat"]),
      lng: safeDouble(data["lng"]),

      description: data["description"],

      companyName: data["companyName"],
      companyLogo: data["companyLogo"],

      photos: safePhotos(data["photos"]),

      jobType: data["jobType"],

      /// NEW FIELDS
      duration: data["duration"],
      startDate: safeDate(data["startDate"]),
      employmentType: data["employmentType"],

      ownerId: data["ownerId"],

      applicantsCount: safeInt(data["applicantsCount"]),

      createdAt: safeDate(data["createdAt"]),
    );
  }
}