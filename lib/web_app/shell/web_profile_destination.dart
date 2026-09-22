enum WebProfileDestination { admin, standard, unavailable }

WebProfileDestination resolveWebProfileDestination({
  required String viewerUid,
  required String viewerRole,
  required String profileUid,
  required String profileRole,
}) {
  if (profileRole != 'admin') return WebProfileDestination.standard;
  return viewerRole == 'admin' && viewerUid == profileUid
      ? WebProfileDestination.admin
      : WebProfileDestination.unavailable;
}
