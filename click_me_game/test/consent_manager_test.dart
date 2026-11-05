import 'package:click_me_game/consent_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

void main() {
  test('release builds never simulate Europe', () {
    final params = ConsentManager.parametersFor(
      isDebug: false,
      simulateEea: true,
      testDeviceId: 'ABC',
    );
    expect(params.consentDebugSettings, isNull);
  });

  test('debug builds simulate Europe only when asked', () {
    expect(
      ConsentManager.parametersFor(
        isDebug: true,
        simulateEea: false,
        testDeviceId: '',
      ).consentDebugSettings,
      isNull,
    );

    final settings = ConsentManager.parametersFor(
      isDebug: true,
      simulateEea: true,
      testDeviceId: 'ABC',
    ).consentDebugSettings;
    expect(settings?.debugGeography, DebugGeography.debugGeographyEea);
    expect(settings?.testIdentifiers, ['ABC']);
  });
}
