import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String id;

  /// worker / employer
  final String role;

  final String? name;
  final String? phone;

  /// worker
  final String? trade;

  /// NEW: experience in years
  final int? experienceYears;
  final int? experienceMonths;

  /// NEW: expected rate (£/hour or day)
  final double? rate;

  /// NEW: availability (immediate / date string)
  final String? availability;

  /// NEW: travel radius in miles
  final double? radius;

  /// NEW: certifications (CSCS etc.)
  final List<String>? certifications;

  final List<Map<String, dynamic>>? references;

  /// employer
  final String? companyName;

  /// NEW: rating system
  final double rating;
  final int reviewsCount;

  final DateTime? createdAt;

  AppUser({
    required this.id,
    required this.role,
    this.name,
    this.phone,
    this.trade,
    this.experienceYears,
    this.experienceMonths,
    this.rate,
    this.availability,
    this.radius,
    this.certifications,
    this.references,
    this.companyName,
    this.rating = 0,
    this.reviewsCount = 0,
    this.createdAt,
  });

  /// 🔥 READY PROFILE CHECK (для apply)
  bool get isProfileComplete {
    if (role != "worker") return true;

    return trade != null &&
        trade!.isNotEmpty &&
        rate != null &&
        availability != null;
  }

  /// 💰 rate text
  String get rateText {
    if (rate == null) return "";

    return "£${rate!.toInt()}/hour";
  }

  factory AppUser.fromFirestore(String id, Map<String, dynamic> data) {
    DateTime? safeDate(dynamic value) {
      if (value == null) return null;

      if (value is Timestamp) {
        return value.toDate();
      }

      return null;
    }

    double? safeDouble(dynamic value) {
      if (value == null) return null;

      if (value is int) return value.toDouble();

      if (value is double) return value;

      if (value is String) {
        return double.tryParse(value);
      }

      return null;
    }

    int? safeInt(dynamic value) {
      if (value == null) return null;

      if (value is int) return value;

      if (value is double) return value.toInt();

      return null;
    }

    List<String>? safeList(dynamic value) {
      if (value == null) return null;

      if (value is List) {
        return value.map((e) => e.toString()).toList();
      }

      return null;
    }

    List<Map<String, dynamic>>? safeMapList(dynamic value) {
      if (value == null) return null;

      if (value is List) {
        return value
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }

      return null;
    }

    return AppUser(
      id: id,
      role: data["role"] ?? "worker",
      name: data["name"],
      phone: data["phone"],
      trade: data["trade"],
      experienceYears: safeInt(data["experienceYears"]),
      experienceMonths: safeInt(data["experienceMonths"]),
      rate: safeDouble(data["rate"]),
      availability: data["availability"],
      radius: safeDouble(data["radius"]),
      certifications: safeList(data["certifications"]),
      references: safeMapList(data["references"]),
      companyName: data["companyName"],
      rating: safeDouble(data["rating"]) ?? 0,
      reviewsCount: safeInt(data["reviewsCount"]) ?? 0,
      createdAt: safeDate(data["createdAt"]),
    );
  }
}
