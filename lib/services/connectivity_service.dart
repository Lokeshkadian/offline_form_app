import 'package:connectivity_plus/connectivity_plus.dart';

import 'api_service.dart';

class ConnectivityService {
  ConnectivityService({Connectivity? connectivity, ApiService? api})
    : _connectivity = connectivity ?? Connectivity(),
      _api = api ?? ApiService();

  final Connectivity _connectivity;
  final ApiService _api;

  Stream<List<ConnectivityResult>> get onChanged =>
      _connectivity.onConnectivityChanged;

  Future<bool> isOnline() async {
    final results = await _connectivity.checkConnectivity();

    final hasNetwork = results.any(
      (result) => result != ConnectivityResult.none,
    );
    if (!hasNetwork) return false;

    return _api.checkHealth();
  }
}
