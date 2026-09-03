import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:raze_store/core/widgets/bounded_network_image.dart';

void main() {
  testWidgets('renders a valid bounded image response', (tester) async {
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BoundedNetworkImage(
          url: 'https://catalog.example/product.png',
          fallback: const SizedBox(key: ValueKey('fallback')),
          clientFactory: () => MockClient(
            (_) async => http.Response.bytes(
              bytes,
              200,
              headers: {'content-type': 'image/png'},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(find.byKey(const ValueKey('fallback')), findsNothing);
  });

  testWidgets('keeps the fallback when an image exceeds its byte limit', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BoundedNetworkImage(
          url: 'https://catalog.example/large.jpg',
          maximumBytes: 4,
          fallback: const SizedBox(key: ValueKey('fallback')),
          clientFactory: () => MockClient(
            (_) async => http.Response.bytes(
              List<int>.filled(5, 1),
              200,
              headers: {'content-type': 'image/jpeg'},
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 11));
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(find.byKey(const ValueKey('fallback')), findsOneWidget);
  });

  testWidgets('does not request a non-web image URL', (tester) async {
    var requests = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: BoundedNetworkImage(
          url: 'file:///private/product.jpg',
          fallback: const SizedBox(key: ValueKey('fallback')),
          clientFactory: () => MockClient((_) async {
            requests++;
            return http.Response('', 200);
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requests, 0);
    expect(find.byKey(const ValueKey('fallback')), findsOneWidget);
  });
}
