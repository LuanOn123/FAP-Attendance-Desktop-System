# Student code check-in

The student website now uses studentCodeSessionInfo and studentCodeCheckIn. It does not load Google Identity Services. Students enter their student code, tick the presence confirmation, and enter a six-digit secret only when the lecturer enabled it. Teacher Google login remains unchanged.

The backend resolves the normalized student code against Students, requires exactly one match and the matching Enrollments row, and checks the open session, expiry, QR/secret and duplicate attendance under a script lock. The audit note identifies student-code check-in, not Google-verified identity. This flow does not prove that the person entering a code owns that student code.

Deployment order:
1. Update the Apps Script source from backend/apps_script/Code.gs.
2. As an account with deployment permissions, edit the existing deployment and select New version, then Deploy.
3. Verify studentCodeSessionInfo with an invalid QR returns a session/QR error, not a Google login error. With a fresh QR it must return checkInMode: student-code-v1 and only lesson metadata.
4. Deploy Firebase from web_hosting with firebase deploy --only hosting --project fap-attendance-cba45.
5. Scan a fresh QR. Test no-secret and secret modes, mandatory presence, unknown/non-enrolled student code, expired/reset QR and duplicate submission.

The remote deployment was previously blocked by Google's "You do not have permission to perform this action" response. Do not deploy the new frontend ahead of the backend or claim the live flow has been updated until both releases are verified.
