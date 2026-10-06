import 'package:cloud_firestore/cloud_firestore.dart';

class WebSite {
  const WebSite({required this.id, required this.data});

  final String id;
  final Map<String, dynamic> data;

  String get name => (data['name'] ?? '').toString();
  String get status => (data['status'] ?? 'active').toString();
  String get city => (data['city'] ?? '').toString();
  String get postcode => (data['postcode'] ?? '').toString();
}

class WebSitesService {
  WebSitesService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<List<WebSite>> loadEmployerSites(String employerId) async {
    final snapshot = await _db
        .collection('sites')
        .where('employerContextId', isEqualTo: employerId)
        .get();
    return snapshot.docs
        .map((doc) => WebSite(id: doc.id, data: doc.data()))
        .toList();
  }

  Stream<List<WebSite>> watchEmployerSites(String employerId) => _db
          .collection('sites')
          .where('employerContextId', isEqualTo: employerId)
          .snapshots()
          .map((snapshot) {
        final sites = snapshot.docs
            .map((doc) => WebSite(id: doc.id, data: doc.data()))
            .toList();
        sites.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return sites;
      });

  Future<String> create(String employerId, Map<String, dynamic> fields) async {
    final doc = _db.collection('sites').doc();
    await doc.set({
      ...fields,
      'siteId': doc.id,
      'employerContextId': employerId,
      'ownerUid': employerId,
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<void> update(WebSite site, Map<String, dynamic> fields) => _db
      .collection('sites')
      .doc(site.id)
      .update({...fields, 'updatedAt': FieldValue.serverTimestamp()});

  Future<void> setStatus(WebSite site, String status) =>
      _db.collection('sites').doc(site.id).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
        if (status == 'archived') 'archivedAt': FieldValue.serverTimestamp(),
      });
}
