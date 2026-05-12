// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otel_firebase_messaging/otel_firebase_messaging.dart';

class _MemorySpanExporter implements SpanExporter {
  final List<Span> spans = [];
  bool _shutdown = false;

  @override
  Future<void> export(List<Span> s) async {
    if (_shutdown) return;
    spans.addAll(s);
  }

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {
    _shutdown = true;
  }
}

Map<String, Object> _attrs(Span span) =>
    {for (final a in span.attributes.toList()) a.key: a.value};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('tracedMessageHandler', () {
    late _MemorySpanExporter exporter;

    setUp(() async {
      await OTel.reset();
      exporter = _MemorySpanExporter();
      await OTel.initialize(
        serviceName: 'firebase-messaging-otel-test',
        detectPlatformResources: false,
        spanProcessor: SimpleSpanProcessor(exporter),
      );
    });

    tearDown(() async {
      await OTel.shutdown();
      await OTel.reset();
    });

    test('emits CONSUMER span with messaging.* + fcm.* attributes', () async {
      const message = RemoteMessage(
        messageId: 'msg-1',
        from: '/topics/news',
        senderId: '123456',
        collapseKey: 'news',
        contentAvailable: true,
        data: <String, dynamic>{'kind': 'breaking'},
      );

      var handled = false;
      await tracedMessageHandler(
        message,
        handlerType: FcmHandlerType.onMessage,
        handler: (m) async {
          handled = true;
          expect(m.messageId, equals('msg-1'));
        },
        topic: 'news',
      );
      expect(handled, isTrue);

      final span = exporter.spans.single;
      expect(span.kind, equals(SpanKind.consumer));
      expect(span.name, contains('firebase_messaging receive'));
      final attrs = _attrs(span);
      expect(attrs['messaging.system'], equals('fcm'));
      expect(attrs['messaging.operation'], equals('receive'));
      expect(attrs['messaging.message.id'], equals('msg-1'));
      expect(attrs['messaging.destination.name'], equals('news'));
      expect(attrs['messaging.fcm.from'], equals('/topics/news'));
      expect(attrs['messaging.fcm.sender_id'], equals('123456'));
      expect(attrs['messaging.fcm.collapse_key'], equals('news'));
      expect(attrs['messaging.fcm.content_available'], equals(true));
      expect(attrs['messaging.fcm.has_notification'], equals(false));
      expect(attrs['messaging.fcm.handler_type'], equals('on_message'));
    });

    test('extracts traceparent from message.data and stitches to upstream',
        () async {
      // Hand-rolled W3C traceparent: 00-<traceid>-<spanid>-<flags>
      const upstreamTraceId = '4bf92f3577b34da6a3ce929d0e0e4736';
      const upstreamSpanId = '00f067aa0ba902b7';
      const traceparent = '00-$upstreamTraceId-$upstreamSpanId-01';

      const message = RemoteMessage(
        messageId: 'msg-2',
        data: <String, dynamic>{
          'traceparent': traceparent,
          'payload': 'hi',
        },
      );

      await tracedMessageHandler(
        message,
        handlerType: FcmHandlerType.onMessage,
        handler: (_) async {},
      );

      final span = exporter.spans.single;
      // The span's traceId should match the upstream one because
      // W3CTraceContextPropagator.extract gave us a Context with
      // that parent — and the new span's parentSpanId points at
      // the upstream span ID even though there's no in-process
      // parent APISpan.
      expect(span.spanContext.traceId.toString(), equals(upstreamTraceId));
      expect(
        span.spanContext.parentSpanId?.toString(),
        equals(upstreamSpanId),
      );
    });

    test('handler throwing flips span to Error', () async {
      const message = RemoteMessage(messageId: 'msg-3');

      await expectLater(
        tracedMessageHandler(
          message,
          handlerType: FcmHandlerType.onMessage,
          handler: (_) async => throw StateError('boom'),
        ),
        throwsStateError,
      );

      final span = exporter.spans.single;
      expect(span.status, equals(SpanStatusCode.Error));
      expect(_attrs(span)['error.type'], equals('StateError'));
      final events = span.spanEvents ?? [];
      expect(events.any((e) => e.name == 'exception'), isTrue);
    });

    test('handlerType is reflected on the span', () async {
      const message = RemoteMessage(messageId: 'msg-4');
      await tracedMessageHandler(
        message,
        handlerType: FcmHandlerType.onMessageOpenedApp,
        handler: (_) async {},
      );
      expect(
        _attrs(exporter.spans.single)['messaging.fcm.handler_type'],
        equals('on_message_opened_app'),
      );
    });

    test('runWithoutFirebaseMessagingInstrumentationAsync bypasses spans',
        () async {
      const message = RemoteMessage(messageId: 'quiet');
      await runWithoutFirebaseMessagingInstrumentationAsync(() async {
        await tracedMessageHandler(
          message,
          handlerType: FcmHandlerType.onMessage,
          handler: (_) async {},
        );
      });
      expect(exporter.spans, isEmpty);
    });
  });
}
