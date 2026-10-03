import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:offline_form_app/services/api_service.dart';
import 'package:offline_form_app/services/connectivity_service.dart';

class FakeServer {
  final Map<String, Map<String, dynamic>> records = {};
  final List<String> requests = [];
  int _nextId = 1;

  bool connectionLost = false;

  late final ApiService api = ApiService(
    client: MockClient(_handle),
    baseUrlOverride: 'http://fake-server',
  );

  int count(String request) => requests.where((r) => r == request).length;

  Future<http.Response> _handle(http.Request request) async {
    if (connectionLost) {
      throw http.ClientException('Connection lost');
    }

    final method = request.method;
    final path = request.url.path;
    requests.add('$method $path');
    final parts = path.split('/');

    if (path == '/health') {
      return _json({'status': 'ok'});
    }

    if (method == 'GET' && path == '/records') {
      return _json(records.values.toList());
    }

    if (method == 'POST' && path == '/records') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (_shouldFail(body['fullName'])) return _serverError();

      for (final existing in records.values) {
        if (existing['localId'] == body['localId']) {
          return _json(existing);
        }
      }
      final id = '${_nextId++}';
      records[id] = {...body, 'id': id, 'imageUrl': null};
      return _json(records[id], status: 201);
    }

    final id = parts.length > 2 ? parts[2] : '';
    final record = records[id];
    if (record == null) {
      return http.Response('{"error": "Record not found"}', 404);
    }

    if (method == 'PUT') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (_shouldFail(body['fullName'])) return _serverError();
      record.addAll(body);
      return _json(record);
    }

    if (method == 'DELETE') {
      records.remove(id);
      return _json({'message': 'Record deleted'});
    }

    if (method == 'POST' && path.endsWith('/image')) {
      record['imageUrl'] = '/uploads/$id.jpg';
      return _json(record);
    }

    return http.Response('{"error": "Not found"}', 404);
  }

  bool _shouldFail(dynamic fullName) {
    return fullName is String && fullName.toLowerCase().contains('fail');
  }

  http.Response _serverError() {
    return http.Response('{"error": "Simulated server failure"}', 500);
  }

  http.Response _json(Object? data, {int status = 200}) {
    return http.Response(
      jsonEncode(data),
      status,
      headers: {'content-type': 'application/json'},
    );
  }
}

class FakeConnectivity implements ConnectivityService {
  bool online = true;

  @override
  Stream<List<ConnectivityResult>> get onChanged => const Stream.empty();

  @override
  Future<bool> isOnline() async => online;
}
