// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'dart:async';

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'firebase_messaging_semantics.dart';
import 'firebase_messaging_suppression.dart';

const _tracerName = 'dartastic_firebase_messaging_otel';
const _messagingSystem = 'fcm';

/// Handler types for an incoming FCM message. Affects the
/// `messaging.fcm.handler_type` attribute and is useful for
/// distinguishing foreground / tap-launch / cold-start spans in
/// trace search.
enum FcmHandlerType {
  /// `FirebaseMessaging.onMessage` — message arrived while app was
  /// in the foreground.
  onMessage('on_message'),

  /// `FirebaseMessaging.onMessageOpenedApp` — user tapped a
  /// notification to open the app.
  onMessageOpenedApp('on_message_opened_app'),

  /// `FirebaseMessaging.instance.getInitialMessage()` — message
  /// that opened the app from terminated state.
  initialMessage('initial_message'),

  /// `FirebaseMessaging.onBackgroundMessage` — handler invoked in
  /// background isolate. **Background-isolate spans almost always
  /// require a separate OTel.initialize in that isolate.**
  background('background');

  const FcmHandlerType(this.value);

  /// Value used as `messaging.fcm.handler_type` attribute.
  final String value;
}

Tracer _tracer() => OTel.tracerProvider().getTracer(_tracerName);

Attributes _baseAttrs({
  required FcmHandlerType handlerType,
  required RemoteMessage message,
  String? topic,
}) {
  final m = <String, Object>{
    Messaging.messagingSystem.key: _messagingSystem,
    FirebaseMessagingSemantics.operation.key: 'receive',
    FirebaseMessagingSemantics.handlerType.key: handlerType.value,
    FirebaseMessagingSemantics.hasNotification.key:
        message.notification != null,
    FirebaseMessagingSemantics.contentAvailable.key: message.contentAvailable,
  };
  if (message.messageId != null) {
    m[FirebaseMessagingSemantics.messageId.key] = message.messageId!;
  }
  if (message.from != null) {
    m[FirebaseMessagingSemantics.from.key] = message.from!;
  }
  if (message.senderId != null) {
    m[FirebaseMessagingSemantics.senderId.key] = message.senderId!;
  }
  if (message.collapseKey != null) {
    m[FirebaseMessagingSemantics.collapseKey.key] = message.collapseKey!;
  }
  if (topic != null) {
    m[FirebaseMessagingSemantics.destinationName.key] = topic;
  }
  return OTel.attributesFromMap(m);
}

/// `RemoteMessage.data` is `Map<String, dynamic>` but trace context
/// is plain strings — wrap it in a String-typed view for the
/// propagator.
class _RemoteMessageGetter implements TextMapGetter<String> {
  _RemoteMessageGetter(this._data);
  final Map<String, dynamic> _data;

  @override
  String? get(String key) {
    final lower = key.toLowerCase();
    for (final entry in _data.entries) {
      if (entry.key.toLowerCase() == lower) {
        final v = entry.value;
        return v is String ? v : v?.toString();
      }
    }
    return null;
  }

  @override
  Iterable<String> keys() => _data.keys;
}

/// Wraps the user's [handler] in a CONSUMER span carrying
/// `messaging.system=fcm`, `messaging.operation=receive`, and FCM
/// metadata. If the inbound `RemoteMessage.data` contains a
/// `traceparent` (and optionally `tracestate`), the span is
/// stitched into that upstream trace via W3C trace context
/// extraction — so a span on the backend that fanned out an FCM
/// push connects to the span on the device that received it.
///
/// Use this directly when you need to apply your own handling
/// strategy (deduplication, manual queue, etc.):
///
/// ```dart
/// FirebaseMessaging.onMessage.listen((message) async {
///   await tracedMessageHandler(
///     message,
///     handlerType: FcmHandlerType.onMessage,
///     handler: (m) async { /* your code */ },
///   );
/// });
/// ```
///
/// Or use the convenience subscribers below.
Future<void> tracedMessageHandler(
  RemoteMessage message, {
  required FcmHandlerType handlerType,
  required Future<void> Function(RemoteMessage) handler,
  String? topic,
}) async {
  if (firebaseMessagingInstrumentationSuppressed()) return handler(message);

  final extractedContext = W3CTraceContextPropagator().extract(
    Context.current,
    message.data.map((k, v) => MapEntry(k, v?.toString() ?? '')),
    _RemoteMessageGetter(message.data),
  );

  final span = _tracer().startSpan(
    'firebase_messaging receive ${message.from ?? "message"}',
    kind: SpanKind.consumer,
    context: extractedContext,
    attributes: _baseAttrs(
      handlerType: handlerType,
      message: message,
      topic: topic,
    ),
  );
  try {
    await handler(message);
  } catch (e, st) {
    span.addAttributes(OTel.attributes([
      OTel.attributeString(
        ErrorResource.errorType.key,
        e.runtimeType.toString(),
      ),
    ]));
    span.recordException(e, stackTrace: st);
    span.setStatus(SpanStatusCode.Error, e.toString());
    rethrow;
  } finally {
    span.end();
  }
}

/// Subscribes [handler] to `FirebaseMessaging.onMessage`, wrapping
/// each message in a CONSUMER span via [tracedMessageHandler].
///
/// Returns the underlying [StreamSubscription] so you can cancel
/// it during shutdown.
StreamSubscription<RemoteMessage> listenForegroundTraced(
  Future<void> Function(RemoteMessage) handler, {
  String? topic,
}) {
  return FirebaseMessaging.onMessage.listen((message) {
    unawaited(tracedMessageHandler(
      message,
      handlerType: FcmHandlerType.onMessage,
      handler: handler,
      topic: topic,
    ));
  });
}

/// Subscribes [handler] to `FirebaseMessaging.onMessageOpenedApp`,
/// wrapping each message in a CONSUMER span.
StreamSubscription<RemoteMessage> listenOpenedAppTraced(
  Future<void> Function(RemoteMessage) handler, {
  String? topic,
}) {
  return FirebaseMessaging.onMessageOpenedApp.listen((message) {
    unawaited(tracedMessageHandler(
      message,
      handlerType: FcmHandlerType.onMessageOpenedApp,
      handler: handler,
      topic: topic,
    ));
  });
}

/// Wraps `FirebaseMessaging.instance.getInitialMessage()` and, when
/// it resolves to a non-null message, invokes [handler] in a
/// CONSUMER span.
Future<void> handleInitialMessageTraced(
  Future<void> Function(RemoteMessage) handler, {
  String? topic,
}) async {
  final initial = await FirebaseMessaging.instance.getInitialMessage();
  if (initial == null) return;
  await tracedMessageHandler(
    initial,
    handlerType: FcmHandlerType.initialMessage,
    handler: handler,
    topic: topic,
  );
}

/// Traced topic-management calls. Emits a PRODUCER span per call.
extension OTelFirebaseMessaging on FirebaseMessaging {
  /// Traced `subscribeToTopic`.
  Future<void> tracedSubscribeToTopic(String topic) async {
    if (firebaseMessagingInstrumentationSuppressed()) {
      return subscribeToTopic(topic);
    }
    final span = _tracer().startSpan(
      'firebase_messaging subscribe $topic',
      kind: SpanKind.producer,
      attributes: OTel.attributesFromMap(<String, Object>{
        Messaging.messagingSystem.key: _messagingSystem,
        FirebaseMessagingSemantics.operation.key: 'subscribe',
        FirebaseMessagingSemantics.destinationName.key: topic,
      }),
    );
    try {
      await subscribeToTopic(topic);
    } catch (e, st) {
      span.recordException(e, stackTrace: st);
      span.setStatus(SpanStatusCode.Error, e.toString());
      rethrow;
    } finally {
      span.end();
    }
  }

  /// Traced `unsubscribeFromTopic`.
  Future<void> tracedUnsubscribeFromTopic(String topic) async {
    if (firebaseMessagingInstrumentationSuppressed()) {
      return unsubscribeFromTopic(topic);
    }
    final span = _tracer().startSpan(
      'firebase_messaging unsubscribe $topic',
      kind: SpanKind.producer,
      attributes: OTel.attributesFromMap(<String, Object>{
        Messaging.messagingSystem.key: _messagingSystem,
        FirebaseMessagingSemantics.operation.key: 'unsubscribe',
        FirebaseMessagingSemantics.destinationName.key: topic,
      }),
    );
    try {
      await unsubscribeFromTopic(topic);
    } catch (e, st) {
      span.recordException(e, stackTrace: st);
      span.setStatus(SpanStatusCode.Error, e.toString());
      rethrow;
    } finally {
      span.end();
    }
  }
}
