import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Shows Google's consent message to players who need it (EEA, UK and
/// Switzerland), using the message published in AdMob > Privacy & messaging.
///
/// To test from outside Europe, run a debug build with:
///   --dart-define=CONSENT_DEBUG_EEA=true
///   --dart-define=CONSENT_TEST_DEVICE_ID=<the ID printed in the device log>
/// Both are ignored in release builds.
class ConsentManager {
  static const bool _simulateEea = bool.fromEnvironment('CONSENT_DEBUG_EEA');
  static const String _testDeviceId = String.fromEnvironment(
    'CONSENT_TEST_DEVICE_ID',
  );

  /// Checks consent, showing the message if required.
  ///
  /// [onChanged] runs after the check and again after the message closes. It
  /// also runs after errors, because Google may still allow ads based on the
  /// player's choice from an earlier session.
  static void gatherConsent(VoidCallback onChanged) {
    ConsentInformation.instance.requestConsentInfoUpdate(
      parametersFor(
        isDebug: kDebugMode,
        simulateEea: _simulateEea,
        testDeviceId: _testDeviceId,
      ),
      () {
        onChanged();
        ConsentForm.loadAndShowConsentFormIfRequired((error) {
          if (error != null) {
            debugPrint('Consent form error: ${error.message}');
          }
          onChanged();
        });
      },
      (error) {
        debugPrint('Consent check error: ${error.message}');
        onChanged();
      },
    );
  }

  static Future<bool> canRequestAds() =>
      ConsentInformation.instance.canRequestAds();

  /// Whether this player must be offered a way to change their choice.
  static Future<bool> isPrivacyOptionsRequired() async {
    final status = await ConsentInformation.instance
        .getPrivacyOptionsRequirementStatus();
    return status == PrivacyOptionsRequirementStatus.required;
  }

  static void showPrivacyOptions() {
    ConsentForm.showPrivacyOptionsForm((error) {
      if (error != null) {
        debugPrint('Privacy options error: ${error.message}');
      }
    });
  }

  @visibleForTesting
  static ConsentRequestParameters parametersFor({
    required bool isDebug,
    required bool simulateEea,
    required String testDeviceId,
  }) {
    if (!isDebug || !simulateEea) return ConsentRequestParameters();
    return ConsentRequestParameters(
      consentDebugSettings: ConsentDebugSettings(
        debugGeography: DebugGeography.debugGeographyEea,
        testIdentifiers: testDeviceId.isEmpty ? null : [testDeviceId],
      ),
    );
  }
}
