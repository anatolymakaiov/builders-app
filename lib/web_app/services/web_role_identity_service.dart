import 'package:cloud_firestore/cloud_firestore.dart';

class WebRoleIdentity {
  const WebRoleIdentity({
    required this.userId,
    required this.role,
    required this.displayName,
    required this.avatarUrl,
    required this.subtitle,
    required this.data,
  });

  final String userId;
  final String role;
  final String displayName;
  final String avatarUrl;
  final String subtitle;
  final Map<String, dynamic> data;
}

class WebRoleIdentityResolver {
  WebRoleIdentityResolver({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final _cache = <String, WebRoleIdentity>{};

  Future<WebRoleIdentity> resolve({
    required String userId,
    String? role,
    Map<String, dynamic>? profile,
    bool useCache = true,
  }) async {
    final cacheKey = '$userId:${role ?? ''}';
    if (useCache && profile == null && _cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }
    final data = profile ??
        (await _firestore.collection('users').doc(userId).get()).data() ??
        const <String, dynamic>{};
    final resolvedRole =
        (role ?? data['role'] ?? '').toString().trim().toLowerCase();
    final identity = resolvedRole == 'employer'
        ? _employer(userId, data)
        : _worker(userId, resolvedRole.isEmpty ? 'worker' : resolvedRole, data);
    _cache[cacheKey] = identity;
    return identity;
  }

  WebRoleIdentity _worker(
    String userId,
    String role,
    Map<String, dynamic> data,
  ) {
    return WebRoleIdentity(
      userId: userId,
      role: role,
      displayName: _firstText(
        data,
        const ['name', 'displayName', 'firstName', 'fullName', 'email'],
        'Worker',
      ),
      avatarUrl: _firstText(
        data,
        const ['photo', 'avatarUrl', 'profilePhotoUrl', 'photoUrl'],
        '',
      ),
      subtitle: _firstText(
        data,
        const ['trade', 'position', 'roleTitle', 'profession'],
        'Worker account',
      ),
      data: data,
    );
  }

  WebRoleIdentity _employer(String userId, Map<String, dynamic> data) {
    return WebRoleIdentity(
      userId: userId,
      role: 'employer',
      displayName: _firstText(
        data,
        const ['companyName', 'businessName', 'displayName', 'name', 'email'],
        'Company',
      ),
      avatarUrl: _firstText(
        data,
        const [
          'companyLogoUrl',
          'companyLogo',
          'companyAvatarUrl',
          'logo',
          'employerAvatarUrl',
          'avatarUrl',
          'photoUrl',
          'photo',
        ],
        '',
      ),
      subtitle: _firstText(
        data,
        const ['companyType', 'businessType', 'industry', 'trade'],
        'Employer account',
      ),
      data: data,
    );
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
}
