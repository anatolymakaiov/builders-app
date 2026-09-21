import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../../models/job.dart';
import '../../services/application_status_utils.dart';
import '../../services/billing_service.dart';
import '../../services/job_taxonomy_service.dart';
import '../../services/moderation_hold_service.dart';
import '../../services/offer_acceptance_service.dart';
import 'web_media_pipeline.dart';

class WebJobManagementService {
  WebJobManagementService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
    FirebaseStorage? storage,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;

  Future<String> createVacancy(Map<String, dynamic> jobData) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Please sign in to post a vacancy.');
    if (await ModerationHoldService().isCurrentUserHeld()) {
      throw StateError(ModerationHoldService.suspensionSnackBarMessage);
    }
    await BillingService().assertEmployerCanPost(user.uid);
    final result = await _functions
        .httpsCallable('createVacancyWithEntitlement')
        .call<Map<String, dynamic>>({'jobData': callablePayload(jobData)});
    return result.data['jobId']?.toString() ?? '';
  }

  Future<String> submitVacancyEditReview({
    required String jobId,
    required Map<String, dynamic> proposedChanges,
  }) async {
    final result = await _functions
        .httpsCallable('submitVacancyEditReview')
        .call<Map<String, dynamic>>({
      'jobId': jobId,
      'proposedChanges': callablePayload(proposedChanges),
    });
    return result.data['reviewId']?.toString() ?? '';
  }

  Future<void> setJobActive(Job job, bool active) async {
    final nextStatus = active ? 'active' : 'closed';
    if (active && job.moderationStatus == 'approved') {
      await BillingService().assertEmployerCanPost(job.ownerId);
    }
    await _firestore.collection('jobs').doc(job.id).set({
      'status': nextStatus,
      if (job.moderationStatus == 'approved') 'billingCounted': active,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (job.moderationStatus == 'approved') {
      await BillingService().syncUsedJobPosts(job.ownerId);
    }
  }

  Future<void> deleteJob(Job job) async {
    await _firestore.collection('jobs').doc(job.id).delete();
  }

  Future<List<String>> pickAndUploadPhotos({
    required String ownerId,
    required String mediaScope,
    void Function(int completed, int total)? onProgress,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    final files = (result?.files ?? const <PlatformFile>[])
        .where((file) => file.bytes != null)
        .toList();
    var completed = 0;
    final batchId = DateTime.now().microsecondsSinceEpoch;
    final uploadedPaths = <String>[];
    onProgress?.call(0, files.length);
    try {
      return await WebMediaPipeline.mapBounded(
        files,
        (file, index) async {
          final url = await uploadPhotoBytes(
            bytes: file.bytes!,
            fileName: file.name,
            extension: file.extension,
            ownerId: ownerId,
            mediaScope: mediaScope,
            storageId: '${batchId}_$index',
            onStored: uploadedPaths.add,
          );
          completed++;
          onProgress?.call(completed, files.length);
          return url;
        },
      );
    } catch (_) {
      await WebMediaPipeline.mapBounded(
        List<String>.from(uploadedPaths),
        (path, _) async {
          try {
            await _storage.ref(path).delete();
          } catch (_) {
            // Best-effort cleanup for an incomplete upload batch.
          }
        },
      );
      rethrow;
    }
  }

  Future<String> uploadPhotoBytes({
    required Uint8List bytes,
    required String fileName,
    required String ownerId,
    required String mediaScope,
    String? extension,
    String? storageId,
    void Function(String path)? onStored,
  }) async {
    final contentType = _contentType(extension ?? fileName);
    final media = await WebMediaPipeline.optimizeImage(
      bytes: bytes,
      fileName: fileName,
      contentType: contentType,
    );
    final safeName = media.fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final safeOwner = _safeStorageSegment(ownerId, fallback: 'unknown-owner');
    final safeScope = _safeStorageSegment(mediaScope, fallback: 'draft');
    final uploadId = storageId ?? DateTime.now().microsecondsSinceEpoch;
    final path = 'job_photos/${safeOwner}_${safeScope}_${uploadId}_$safeName';
    final ref = _storage.ref(path);
    await ref.putData(
      media.bytes,
      SettableMetadata(
        contentType: media.contentType,
        cacheControl: WebMediaPipeline.browserCacheControl,
      ),
    );
    onStored?.call(path);
    return ref.getDownloadURL();
  }

  Future<String> companyName(String employerId) async {
    final doc = await _firestore.collection('users').doc(employerId).get();
    final data = doc.data();
    final name =
        _firstText(data, const ['companyName', 'name', 'displayName'], '');
    if (name.isNotEmpty) return name;
    return _auth.currentUser?.email ?? 'Company';
  }

  Future<WebJobApplicationStats> applicationStats(String jobId) async {
    final snapshot = await _firestore
        .collection('applications')
        .where('jobId', isEqualTo: jobId)
        .get();
    var review = 0;
    var offers = 0;
    var acceptedSlots = 0;
    var rejectedWithdrawn = 0;
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final status = ApplicationStatusUtils.normalizeStatus(data['status']);
      if (status == 'pending') review++;
      if (ApplicationStatusUtils.isStatusInFilter(
        status,
        ApplicationStatusUtils.offerFilter,
      )) {
        offers++;
      }
      if (OfferAcceptanceService.isAcceptedStatus(status)) {
        acceptedSlots += OfferAcceptanceService.applicationSlotCount(data);
      }
      if (status == 'rejected' || status == 'withdrawn') {
        rejectedWithdrawn++;
      }
    }
    return WebJobApplicationStats(
      total: snapshot.docs.length,
      inReview: review,
      offers: offers,
      acceptedSlots: acceptedSlots,
      rejectedWithdrawn: rejectedWithdrawn,
    );
  }

  Map<String, dynamic> buildJobData({
    required String ownerId,
    required String title,
    required String site,
    required String duration,
    required String weeklyHours,
    required int positions,
    required int filledPositions,
    required String jobType,
    required double rate,
    required String addressLine1,
    required String addressLine2,
    required String addressLine3,
    required String city,
    required String county,
    required String postcode,
    required String country,
    required String description,
    required String responsibilities,
    required String candidateRequirements,
    required String requiredDocuments,
    required String additionalInformation,
    required List<String> photos,
    required double lat,
    required double lng,
    required String companyName,
    bool create = true,
  }) {
    final taxonomyRole = JobTaxonomyService.bestRoleFor(title);
    final canonicalTitle = taxonomyRole?.canonical ?? title.trim();
    final canonicalRoleId = JobTaxonomyService.roleIdFor(canonicalTitle);
    final siteAddress = [
      addressLine1,
      addressLine2,
      addressLine3,
      city,
      county,
      postcode,
      country,
    ].where((part) => part.trim().isNotEmpty).join(', ');

    return {
      'ownerId': ownerId,
      'employerId': ownerId,
      'title': canonicalTitle,
      'site': site.trim(),
      'trade': canonicalTitle,
      'canonicalRoleId': canonicalRoleId,
      'canonicalRoleName': canonicalTitle,
      'originalEmployerInput': title.trim(),
      'roleCanonical': canonicalTitle,
      'roleCanonicalId': canonicalRoleId,
      'roleCategory': taxonomyRole?.category ?? '',
      'roleAliases': taxonomyRole?.aliases ?? const <String>[],
      'searchTerms': JobTaxonomyService.searchTermsFor(canonicalTitle),
      'duration': duration.trim(),
      'weeklyHours': weeklyHours.trim(),
      'positions': positions <= 0 ? 1 : positions,
      'filledPositions': filledPositions,
      'street': addressLine1.trim(),
      'addressLine1': addressLine1.trim(),
      'addressLine2': addressLine2.trim(),
      'addressLine3': addressLine3.trim(),
      'city': city.trim(),
      'postcode': postcode.trim(),
      'county': county.trim(),
      'country': country.trim(),
      'location': siteAddress,
      'siteStreet': addressLine1.trim(),
      'siteAddressLine1': addressLine1.trim(),
      'siteAddressLine2': addressLine2.trim(),
      'siteAddressLine3': addressLine3.trim(),
      'siteCity': city.trim(),
      'sitePostcode': postcode.trim(),
      'siteCounty': county.trim(),
      'siteCountry': country.trim(),
      'siteAddress': siteAddress,
      'fullAddress': siteAddress,
      'rate': jobType == 'negotiable' ? 0 : rate,
      'jobType': jobType,
      'companyName': companyName,
      'description': description.trim(),
      'responsibilities': responsibilities.trim(),
      'candidateRequirements': candidateRequirements.trim(),
      'requiredDocuments': requiredDocuments.trim(),
      'additionalInformation': additionalInformation.trim(),
      'photos': photos,
      'lat': lat,
      'lng': lng,
      if (create) 'status': 'active',
      if (create) 'visibility': 'public',
      if (create) 'moderationStatus': 'pending_review',
      if (create) 'moderationReason': '',
      if (create) 'viewedByAdmin': false,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> callablePayload(Map<String, dynamic> data) {
    final next = Map<String, dynamic>.from(data);
    next.removeWhere((_, value) => value is FieldValue);
    return next;
  }

  String _contentType(String value) {
    final extension = value.split('.').last.toLowerCase();
    return switch (extension) {
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'heif' => 'image/heif',
      _ => 'image/jpeg',
    };
  }

  String _safeStorageSegment(String value, {required String fallback}) {
    final clean = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return clean.isEmpty ? fallback : clean;
  }
}

class WebJobApplicationStats {
  const WebJobApplicationStats({
    required this.total,
    required this.inReview,
    required this.offers,
    required this.acceptedSlots,
    required this.rejectedWithdrawn,
  });

  final int total;
  final int inReview;
  final int offers;
  final int acceptedSlots;
  final int rejectedWithdrawn;
}

String _firstText(
  Map<String, dynamic>? data,
  List<String> keys,
  String fallback,
) {
  if (data == null) return fallback;
  for (final key in keys) {
    final value = data[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return fallback;
}
