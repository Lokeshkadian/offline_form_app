import 'package:shared_preferences/shared_preferences.dart';

import '../utils/constants.dart';

class ServerConfig {
  static const String _key = 'server_url';

  static String baseUrl = defaultBaseUrl;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    baseUrl = prefs.getString(_key) ?? defaultBaseUrl;
  }

  static Future<void> save(String url) async {
    baseUrl = clean(url);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, baseUrl);
  }

  static String clean(String url) {
    var result = url.trim();
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  static String fullImageUrl(String imageUrl) {
    if (imageUrl.startsWith('http')) return imageUrl;
    return '$baseUrl$imageUrl';
  }
}
