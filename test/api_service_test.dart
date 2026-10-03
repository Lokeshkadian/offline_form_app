import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:offline_form_app/models/form_record.dart';
import 'package:offline_form_app/services/api_service.dart';

FormRecord makeRecord() {
  return FormRecord(
    localId: 'local-1',
    fullName: 'Asha Kumar',
    mobile: '9876543210',
    email: 'asha@mail.com',
    category: 'Sales Visit',
    description: 'First visit',
    visitDate: DateTime(2026, 10, 1),
    createdAt: DateTime(2026, 10, 1),
    updatedAt: DateTime(2026, 10, 1),
  );
}

ApiService apiAnswering(Future<http.Response> Function(http.Request) answer) {
  return ApiService(
    client: MockClient(answer),
    baseUrlOverride: 'http://test-server',
  );
}

Future<ApiException> errorFrom(Future<void> call) async {
  try {
    await call;
  } on ApiException catch (e) {
    return e;
  }
  fail('Expected an ApiException');
}

void main() {
  test('createRecord sends JSON with localId and returns the record', () async {
    late http.Request sent;
    final api = apiAnswering((request) async {
      sent = request;
      return http.Response('{"id": "server-1", "localId": "local-1"}', 201);
    });

    final data = await api.createRecord(makeRecord());

    expect(data['id'], 'server-1');
    expect(sent.method, 'POST');
    expect(sent.url.toString(), 'http://test-server/records');
    expect(jsonDecode(sent.body)['localId'], 'local-1');
  });

  test('checkHealth is true when the server answers, false when not', () async {
    final up = apiAnswering((_) async => http.Response('{"status":"ok"}', 200));
    final down = apiAnswering((_) async {
      throw const SocketException('Connection refused');
    });

    expect(await up.checkHealth(), true);
    expect(await down.checkHealth(), false);
  });

  test('server errors become friendly messages with the status code', () async {
    final error500 = await errorFrom(
      apiAnswering(
        (_) async => http.Response('oops', 500),
      ).createRecord(makeRecord()),
    );
    expect(error500.message, 'Server error (500)');
    expect(error500.statusCode, 500);
    expect(error500.isConnectionError, false);

    final error404 = await errorFrom(
      apiAnswering((_) async => http.Response('{}', 404)).fetchRecord('x'),
    );
    expect(error404.message, 'Record not found on server (404)');
    expect(error404.statusCode, 404);

    final error400 = await errorFrom(
      apiAnswering(
        (_) async => http.Response('{}', 400),
      ).createRecord(makeRecord()),
    );
    expect(error400.message, 'Request rejected by server (400)');
  });

  test('network problems are connection errors', () async {
    final noServer = await errorFrom(
      apiAnswering((_) async {
        throw http.ClientException('Connection refused');
      }).fetchRecords(),
    );
    expect(noServer.message, 'Server unavailable / no internet');
    expect(noServer.isConnectionError, true);

    final timeout = await errorFrom(
      apiAnswering((_) async {
        throw TimeoutException('too slow');
      }).fetchRecords(),
    );
    expect(timeout.message, 'Request timed out');
    expect(timeout.isConnectionError, true);
  });

  test('a reply that is not a valid record is rejected', () async {
    final notJson = await errorFrom(
      apiAnswering((_) async => http.Response('<html>', 200)).fetchRecord('x'),
    );
    expect(notJson.message, 'Invalid server response');

    final noId = await errorFrom(
      apiAnswering(
        (_) async => http.Response('{"fullName": "Asha"}', 200),
      ).fetchRecord('x'),
    );
    expect(noId.message, 'Invalid server response');
  });

  test('uploadImage fails clearly if the photo file is missing', () async {
    final api = apiAnswering((_) async => http.Response('{"id": "1"}', 200));

    final error = await errorFrom(
      api.uploadImage('server-1', '/no/such/photo.jpg'),
    );
    expect(error.message, 'Image file not found on phone');
  });
}
