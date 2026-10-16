import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';

/// Helper to read fixture JSON or HTML files from `test/fixtures/`.
String loadFixture(String filename) {
  final file = File('test/fixtures/$filename');
  if (!file.existsSync()) {
    throw Exception('Fixture file not found: test/fixtures/$filename');
  }
  return file.readAsStringSync();
}

/// Helper to parse fixture JSON into dynamic Map or List.
dynamic loadFixtureJson(String filename) {
  return json.decode(loadFixture(filename));
}

/// Custom mock adapter implementing Dio's [HttpClientAdapter] interface.
class MockHttpAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) handler;

  MockHttpAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}

  /// Convenience factory returning a static JSON body.
  static MockHttpAdapter jsonResponse(String jsonString, {int statusCode = 200, Map<String, List<String>>? headers}) {
    return MockHttpAdapter((options) async {
      final h = headers ??
          {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          };
      return ResponseBody.fromString(
        jsonString,
        statusCode,
        headers: h,
      );
    });
  }

  /// Convenience factory returning a response from a fixture file.
  static MockHttpAdapter fromFixture(String filename, {int statusCode = 200, Map<String, List<String>>? headers}) {
    return jsonResponse(loadFixture(filename), statusCode: statusCode, headers: headers);
  }
}

/// Creates a mock [Dio] client backed by [MockHttpAdapter].
Dio createMockDio(MockHttpAdapter adapter) {
  final dio = Dio();
  dio.httpClientAdapter = adapter;
  return dio;
}
