/// One entry point for the projected QR and the lecturer's browser preview.
Uri studentCheckinUrl({
  required String sessionId,
  required String token,
  required bool secretEnabled,
}) => Uri.https('fap-attendance-88920.web.app', '/checkin', {
  'sessionId': sessionId,
  'token': token,
  'mode': secretEnabled ? 'google-secret' : 'google',
  'v': '5',
});
