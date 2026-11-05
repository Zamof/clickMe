import 'package:click_me_game/ad_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const realUnit = 'ca-app-pub-2471654882666627/6904439444';
  const googleTestPublisher = 'ca-app-pub-3940256099942544/';

  test('non-release Android builds never use the real ad unit', () {
    expect(
      AdConfig.bannerAdUnitIdFor(
        platform: TargetPlatform.android,
        isRelease: false,
      ),
      startsWith(googleTestPublisher),
    );
  });

  test('release Android builds use the real ad unit', () {
    expect(
      AdConfig.bannerAdUnitIdFor(
        platform: TargetPlatform.android,
        isRelease: true,
      ),
      realUnit,
    );
  });

  test('iOS never uses the Android ad unit', () {
    expect(
      AdConfig.bannerAdUnitIdFor(platform: TargetPlatform.iOS, isRelease: true),
      startsWith(googleTestPublisher),
    );
  });

  test('tests themselves run outside release mode', () {
    expect(AdConfig.bannerAdUnitId, isNot(realUnit));
  });
}
