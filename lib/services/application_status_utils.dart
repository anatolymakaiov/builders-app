import 'package:cloud_firestore/cloud_firestore.dart';

class ApplicationStatusUtils {
  const ApplicationStatusUtils._();

  static const allFilter = "all";
  static const reviewFilter = "review";
  static const negotiationFilter = "negotiation";
  static const offerFilter = "offer";
  static const rejectedFilter = "rejected";
  static const hiredFilter = "hired";
  static const withdrawnFilter = "withdrawn";

  static String normalizeStatus(dynamic value) {
    final raw = value?.toString().toLowerCase().trim() ?? "";
    final status = raw.replaceAll("-", "_").replaceAll(" ", "_");
    if (status.isEmpty) return "pending";

    switch (status) {
      case "applied":
      case "submitted":
      case "review":
      case "in_review":
      case "inreview":
      case "under_review":
        return "pending";
      case "in_negotiation":
      case "negotiating":
        return "negotiation";
      case "offer_received":
        return "offer_sent";
      case "application_rejected":
        return "rejected";
      case "application_withdrawn":
      case "cancelled":
      case "canceled":
      case "deleted":
        return "withdrawn";
      case "hired":
        return "offer_accepted";
      default:
        return status;
    }
  }

  static Set<String> getStatusesForFilter(String filter) {
    switch (filter) {
      case reviewFilter:
      case "sent":
      case "pending":
      case "in_review":
        return {"pending", "submitted", "in_review", "review", "applied"};
      case negotiationFilter:
        return {"negotiation", "in_negotiation", "negotiating"};
      case offerFilter:
        return {
          "offer_sent",
          "offer_received",
          "offer_accepted",
          "offer_rejected",
          "offer_withdrawn",
          "accepted",
          "hired",
        };
      case rejectedFilter:
        return {"rejected", "application_rejected"};
      case hiredFilter:
        return {"offer_accepted", "accepted", "hired"};
      case withdrawnFilter:
        return {
          "withdrawn",
          "application_withdrawn",
          "cancelled",
          "canceled",
          "deleted",
        };
      default:
        return const {};
    }
  }

  static bool isStatusInFilter(dynamic status, String filter) {
    if (filter == allFilter) return true;
    final normalized = normalizeStatus(status);
    final group = getStatusesForFilter(filter).map(normalizeStatus).toSet();
    return group.contains(normalized);
  }

  static String filterForStatus(dynamic status) {
    final normalized = normalizeStatus(status);
    const filters = [
      reviewFilter,
      negotiationFilter,
      offerFilter,
      rejectedFilter,
      hiredFilter,
      withdrawnFilter,
    ];
    for (final filter in filters) {
      if (isStatusInFilter(normalized, filter)) return filter;
    }
    return allFilter;
  }

  static String getStatusDisplayLabel(dynamic status, String role) {
    final normalized = normalizeStatus(status);
    final isEmployer = role == "employer";

    switch (normalized) {
      case "pending":
        return "In Review";
      case "negotiation":
        return "Negotiation";
      case "offer_sent":
        return isEmployer ? "Offer Sent" : "Offer Received";
      case "offer_withdrawn":
        return "Offer Withdrawn";
      case "offer_accepted":
      case "accepted":
        return isEmployer ? "Hired" : "Offer Accepted";
      case "offer_rejected":
        return "Offer Rejected";
      case "rejected":
        return "Rejected";
      case "withdrawn":
        return "Withdrawn";
      default:
        return normalized
            .split("_")
            .where((part) => part.isNotEmpty)
            .map((part) => "${part[0].toUpperCase()}${part.substring(1)}")
            .join(" ");
    }
  }

  static DateTime getStatusSortTimestamp(Map<String, dynamic> application) {
    final value = application["updatedAt"] ??
        application["lastStatusChangedAt"] ??
        application["applicationActivityAt"] ??
        application["lastMessageAt"] ??
        application["createdAt"];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static int compareNewestFirst(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    return getStatusSortTimestamp(b).compareTo(getStatusSortTimestamp(a));
  }
}
