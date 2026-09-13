import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'web_data_state.dart';

class WebProfileData {
  const WebProfileData({
    required this.id,
    required this.data,
  });

  final String id;
  final Map<String, dynamic> data;

  String get displayName {
    return _firstText(
      data,
      const ['companyName', 'name', 'displayName', 'firstName', 'email'],
      'Profile',
    );
  }

  String get avatarUrl {
    return _firstText(
      data,
      const [
        'avatarUrl',
        'photoUrl',
        'profilePhotoUrl',
        'companyLogo',
        'companyLogoUrl',
      ],
      '',
    );
  }

  String get headerUrl {
    return _firstText(
      data,
      const [
        'headerImageUrl',
        'backgroundImageUrl',
        'coverPhotoUrl',
        'companyHeaderUrl',
      ],
      '',
    );
  }
}

class WebProfileDataService {
  WebProfileDataService({
    FirebaseFirestore? firestore,
    this.pollInterval = const Duration(seconds: 12),
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final Duration pollInterval;

  Stream<WebDataState<WebProfileData?>> profile(String uid) {
    Timer? timer;
    var loading = false;
    WebProfileData? lastValue;
    final controller = StreamController<WebDataState<WebProfileData?>>();

    Future<void> refresh() async {
      if (loading || controller.isClosed) return;
      loading = true;
      try {
        final snapshot = await _firestore.collection('users').doc(uid).get();
        final data = snapshot.data();
        lastValue = data == null ? null : WebProfileData(id: uid, data: data);
        if (!controller.isClosed) controller.add(WebDataState.data(lastValue));
      } catch (error) {
        debugPrint('WEB PROFILE LOAD ERROR $error');
        if (!controller.isClosed) {
          controller.add(WebDataState.error(error, lastData: lastValue));
        }
      } finally {
        loading = false;
      }
    }

    controller.onListen = () {
      controller.add(const WebDataState.loading());
      unawaited(refresh());
      timer = Timer.periodic(pollInterval, (_) => unawaited(refresh()));
    };
    controller.onCancel = () => timer?.cancel();
    return controller.stream;
  }
}

String _firstText(
  Map<String, dynamic> data,
  List<String> keys,
  String fallback,
) {
  for (final key in keys) {
    final value = data[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return fallback;
}
