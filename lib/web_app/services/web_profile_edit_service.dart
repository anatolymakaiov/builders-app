import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

class WebProfileEditService {
  WebProfileEditService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  Future<void> saveUserProfile({
    required String uid,
    required Map<String, dynamic> updates,
  }) async {
    await _firestore.collection('users').doc(uid).set({
      ...updates,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<String?> pickAndUploadProfileImage({
    required String uid,
    required bool isEmployer,
  }) async {
    final picked = await _pickSingleImage();
    if (picked == null) return null;
    final url = await _uploadBytes(
      bytes: picked.bytes!,
      path: 'profile_photos/${uid}_${_stamp()}_${picked.safeName}',
      contentType: picked.contentType,
    );
    await saveUserProfile(
      uid: uid,
      updates: {
        'avatarUrl': url,
        'photoUrl': url,
        'profilePhotoUrl': url,
        if (isEmployer) 'companyLogo': url,
        if (isEmployer) 'companyLogoUrl': url,
        if (isEmployer) 'companyAvatarUrl': url,
      },
    );
    return url;
  }

  Future<String?> pickAndUploadHeaderImage(String uid) async {
    final picked = await _pickSingleImage();
    if (picked == null) return null;
    final url = await _uploadBytes(
      bytes: picked.bytes!,
      path: 'profile_headers/$uid.jpg',
      contentType: picked.contentType,
    );
    await saveUserProfile(
      uid: uid,
      updates: {
        'profileHeaderImage': url,
        'headerImage': url,
        'headerImageUrl': url,
        'backgroundImageUrl': url,
        'coverPhotoUrl': url,
      },
    );
    return url;
  }

  Future<List<String>> pickAndAddCompanyPhotos(String uid) async {
    final picked = await _pickImages();
    if (picked.isEmpty) return const [];
    final urls = <String>[];
    for (final file in picked) {
      urls.add(await _uploadBytes(
        bytes: file.bytes!,
        path: 'company_photos/$uid/${_stamp()}_${file.safeName}',
        contentType: file.contentType,
      ));
    }
    await saveUserProfile(
      uid: uid,
      updates: {'companyPhotos': FieldValue.arrayUnion(urls)},
    );
    return urls;
  }

  Future<List<String>> pickAndAddWorkerPortfolio(String uid) async {
    final picked = await _pickImages();
    if (picked.isEmpty) return const [];
    final urls = <String>[];
    final batch = _firestore.batch();
    for (final file in picked) {
      final url = await _uploadBytes(
        bytes: file.bytes!,
        path: 'portfolio/$uid/${_stamp()}_${file.safeName}',
        contentType: file.contentType,
      );
      urls.add(url);
      final ref =
          _firestore.collection('users').doc(uid).collection('portfolio').doc();
      batch.set(ref, {'url': url, 'createdAt': FieldValue.serverTimestamp()});
    }
    batch.set(
      _firestore.collection('users').doc(uid),
      {
        'portfolio': FieldValue.arrayUnion(urls),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
    return urls;
  }

  Future<void> removeCompanyPhoto({
    required String uid,
    required String url,
  }) {
    return saveUserProfile(
      uid: uid,
      updates: {
        'companyPhotos': FieldValue.arrayRemove([url])
      },
    );
  }

  Future<void> removePortfolioPhoto({
    required String uid,
    required String url,
  }) async {
    final batch = _firestore.batch();
    batch.set(
      _firestore.collection('users').doc(uid),
      {
        'portfolio': FieldValue.arrayRemove([url]),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    final docs = await _firestore
        .collection('users')
        .doc(uid)
        .collection('portfolio')
        .where('url', isEqualTo: url)
        .get();
    for (final doc in docs.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  Future<String> createTeam({
    required String ownerId,
    required String name,
    required String description,
    required String trade,
  }) async {
    final doc = await _firestore.collection('teams').add({
      'name': name.trim(),
      'teamName': name.trim(),
      'description': description.trim(),
      if (trade.trim().isNotEmpty) 'trade': trade.trim(),
      'ownerId': ownerId,
      'createdBy': ownerId,
      'leaderId': ownerId,
      'members': [ownerId],
      'memberIds': [ownerId],
      'memberStatuses': {ownerId: 'active'},
      'membersStatus': {ownerId: 'active'},
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<void> saveTeam({
    required String teamId,
    required Map<String, dynamic> updates,
  }) {
    return _firestore.collection('teams').doc(teamId).set({
      ...updates,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<String?> pickAndUploadTeamImage({
    required String teamId,
    required bool header,
  }) async {
    final picked = await _pickSingleImage();
    if (picked == null) return null;
    final path = header
        ? 'team_avatars/${teamId}_header_${_stamp()}.${picked.extension}'
        : 'team_avatars/${teamId}_${_stamp()}.${picked.extension}';
    final url = await _uploadBytes(
      bytes: picked.bytes!,
      path: path,
      contentType: picked.contentType,
    );
    await saveTeam(
      teamId: teamId,
      updates: header
          ? {
              'headerImageUrl': url,
              'profileHeaderImage': url,
              'headerImage': url,
              'backgroundUrl': url,
              'backgroundImage': url,
            }
          : {
              'avatarUrl': url,
              'photo': url,
              'photoUrl': url,
              'teamLogo': url,
            },
    );
    return url;
  }

  Future<WebPickedFile?> _pickSingleImage() async {
    final files = await _pickImages(allowMultiple: false);
    return files.isEmpty ? null : files.first;
  }

  Future<List<WebPickedFile>> _pickImages({bool allowMultiple = true}) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: allowMultiple,
      type: FileType.image,
      withData: true,
    );
    return (result?.files ?? const <PlatformFile>[])
        .where((file) => file.bytes != null)
        .map(WebPickedFile.fromPlatformFile)
        .toList();
  }

  Future<String> _uploadBytes({
    required Uint8List bytes,
    required String path,
    required String contentType,
  }) async {
    final ref = _storage.ref().child(path);
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    return ref.getDownloadURL();
  }

  String _stamp() => DateTime.now().millisecondsSinceEpoch.toString();
}

class WebPickedFile {
  const WebPickedFile({
    required this.name,
    required this.safeName,
    required this.extension,
    required this.bytes,
    required this.contentType,
  });

  final String name;
  final String safeName;
  final String extension;
  final Uint8List? bytes;
  final String contentType;

  factory WebPickedFile.fromPlatformFile(PlatformFile file) {
    final extension =
        (file.extension ?? 'jpg').toLowerCase().replaceAll('.', '');
    final cleanName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return WebPickedFile(
      name: file.name,
      safeName: cleanName.isEmpty ? 'image.$extension' : cleanName,
      extension: extension.isEmpty ? 'jpg' : extension,
      bytes: file.bytes,
      contentType: _contentType(extension),
    );
  }

  static String _contentType(String extension) {
    return switch (extension.toLowerCase()) {
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'heif' => 'image/heif',
      _ => 'image/jpeg',
    };
  }
}
