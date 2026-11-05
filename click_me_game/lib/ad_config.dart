import 'package:flutter/foundation.dart';

/// Picks which AdMob banner the app asks for.
///
/// Only a release build on Android uses the real ad unit. Debug and profile
/// builds always use Google's test units, so tapping an ad during development
/// can never count as invalid traffic on the real account.
class AdConfig {
  static const String _realAndroidBanner =
      'ca-app-pub-2471654882666627/6904439444';

  // Google's public test units: https://developers.google.com/admob/flutter/test-ads
  static const String _testAndroidBanner =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _testIosBanner = 'ca-app-pub-3940256099942544/2934735716';

  static String get bannerAdUnitId => bannerAdUnitIdFor(
    platform: defaultTargetPlatform,
    isRelease: kReleaseMode,
  );

  @visibleForTesting
  static String bannerAdUnitIdFor({
    required TargetPlatform platform,
    required bool isRelease,
  }) {
    // There is no real iOS ad unit yet, so iOS always gets the test unit.
    if (platform == TargetPlatform.iOS) return _testIosBanner;
    return isRelease ? _realAndroidBanner : _testAndroidBanner;
  }
}
