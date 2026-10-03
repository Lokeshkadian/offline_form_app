import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/form_record.dart';
import '../utils/constants.dart';
import 'server_config.dart';

class ApiException implements Exception {
  final String message;

  final int? statusCode;

  final bool isConnectionError;

  ApiException(this.message, {this.statusCode, this.isConnectionError = false});

  @override
  String toString() => message;
}

class ApiService {
  final http.Client _client;
  final String? baseUrlOverride;

  ApiService({http.Client? client, this.baseUrlOverride})
    : _client = client ?? http.Client();

  String get _baseUrl => baseUrlOverride ?? ServerConfig.baseUrl;

  Future<bool> checkHealth() async {
    try {
      await _send(() => _client.get(_url('/health')), timeout: healthTimeout);
      return true;
    } on ApiException {
      return false;
    }
  }

  Future<Map<String, dynamic>> createRecord(FormRecord record) async {
    final response = await _send(
      () => _client.post(
        _url('/records'),
        headers: _jsonHeaders,
        body: jsonEncode(_recordToJson(record)),
      ),
    );
    return _decodeRecord(response.body);
  }

  Future<Map<String, dynamic>> updateRecord(
    String serverId,
    FormRecord record,
  ) async {
    final response = await _send(
      () => _client.put(
        _url('/records/$serverId'),
        headers: _jsonHeaders,
        body: jsonEncode(_recordToJson(record)),
      ),
    );
    return _decodeRecord(response.body);
  }

  Future<void> deleteRecord(String serverId) async {
    await _send(() => _client.delete(_url('/records/$serverId')));
  }

  Future<List<Map<String, dynamic>>> fetchRecords() async {
    final response = await _send(() => _client.get(_url('/records')));

    final data = _decodeJson(response.body);
    if (data is! List) {
      throw ApiException('Invalid server response');
    }

    final records = <Map<String, dynamic>>[];
    for (final item in data) {
      records.add(_checkRecord(item));
    }
    return records;
  }

  Future<Map<String, dynamic>> fetchRecord(String serverId) async {
    final response = await _send(() => _client.get(_url('/records/$serverId')));
    return _decodeRecord(response.body);
  }

  Future<Map<String, dynamic>> uploadImage(
    String serverId,
    String filePath,
  ) async {
    if (!File(filePath).existsSync()) {
      throw ApiException('Image file not found on phone');
    }

    final response = await _send(() async {
      final request = http.MultipartRequest(
        'POST',
        _url('/records/$serverId/image'),
      );
      request.files.add(await http.MultipartFile.fromPath('image', filePath));

      final streamed = await _client.send(request);
      return http.Response.fromStream(streamed);
    }, timeout: uploadTimeout);

    return _decodeRecord(response.body);
  }

  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json',
  };

  Uri _url(String path) => Uri.parse('$_baseUrl$path');

  Future<http.Response> _send(
    Future<http.Response> Function() request, {
    Duration timeout = requestTimeout,
  }) async {
    final http.Response response;
    try {
      response = await request().timeout(timeout);
    } on TimeoutException {
      throw ApiException('Request timed out', isConnectionError: true);
    } on SocketException {
      throw ApiException(
        'Server unavailable / no internet',
        isConnectionError: true,
      );
    } on http.ClientException {
      throw ApiException(
        'Server unavailable / no internet',
        isConnectionError: true,
      );
    }

    final code = response.statusCode;
    if (code >= 200 && code < 300) {
      return response;
    } else if (code == 404) {
      throw ApiException('Record not found on server (404)', statusCode: code);
    } else if (code >= 400 && code < 500) {
      throw ApiException(
        'Request rejected by server ($code)',
        statusCode: code,
      );
    } else {
      throw ApiException('Server error ($code)', statusCode: code);
    }
  }

  dynamic _decodeJson(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      throw ApiException('Invalid server response');
    }
  }

  Map<String, dynamic> _decodeRecord(String body) {
    return _checkRecord(_decodeJson(body));
  }

  Map<String, dynamic> _checkRecord(dynamic data) {
    if (data is Map<String, dynamic> && data['id'] != null) {
      return data;
    }
    throw ApiException('Invalid server response');
  }

  Map<String, dynamic> _recordToJson(FormRecord record) {
    return {
      'localId': record.localId,
      'fullName': record.fullName,
      'mobile': record.mobile,
      'email': record.email,
      'category': record.category,
      'description': record.description,
      'visitDate': record.visitDate.toIso8601String(),
      'createdAt': record.createdAt.toIso8601String(),
      'updatedAt': record.updatedAt.toIso8601String(),
    };
  }
}
