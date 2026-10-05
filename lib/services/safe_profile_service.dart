import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Self reads retain the private profile; every other display read uses the
/// server-maintained, contact-free projection.
class SafeProfileService {
  SafeProfileService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  static String collectionFor(
          {required String? viewerUid, required String targetUid}) =>
      viewerUid == targetUid ? 'users' : 'public_profiles';

  DocumentReference<Map<String, dynamic>> profile(String userId) => _firestore
      .collection(
          collectionFor(viewerUid: _auth.currentUser?.uid, targetUid: userId))
      .doc(userId);

  CollectionReference<Map<String, dynamic>> get publicProfiles =>
      _firestore.collection('public_profiles');
}
