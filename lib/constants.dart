import 'dart:io';

class AppConstants {
  static String get baseUrl {
    if (Platform.isIOS) {
      return 'http://127.0.0.1:5000';
    } else {
      return 'http://10.0.2.2:5000';
    }
  }
}