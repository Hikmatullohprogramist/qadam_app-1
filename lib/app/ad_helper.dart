import 'dart:io';

class AdHelper {
  static String get bannerAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-7180097986291909/8025536468';
    } else if (Platform.isIOS) {
      return 'ca-app-pub-7180097986291909/8025536468';
    } else {
      throw new UnsupportedError('Unsupported platform');
    }
  }

  static String get interstitialAdUnitId {
    if (Platform.isAndroid) {
      return "ca-app-pub-6135925976729797/9497923905";
    } else if (Platform.isIOS) {
      return "ca-app-pub-6135925976729797/9497923905";
    } else {
      throw new UnsupportedError("Unsupported platform");
    }
  }

  static String get rewardedAdUnitId {
    if (Platform.isAndroid) {
      return "ca-app-pub-6135925976729797/9497923905";
    } else if (Platform.isIOS) {
      return "ca-app-pub-6135925976729797/9497923905";
    } else {
      throw new UnsupportedError("Unsupported platform");
    }
  }
}
