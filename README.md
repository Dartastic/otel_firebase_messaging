# otel_firebase_messaging

OpenTelemetry instrumentation for
[`package:firebase_messaging`](https://pub.dev/packages/firebase_messaging)
(FCM), built on the
[Dartastic OpenTelemetry SDK](https://pub.dev/packages/dartastic_opentelemetry).

Wraps inbound `RemoteMessage` handlers in CONSUMER spans, extracts
W3C trace context from `message.data` for end-to-end propagation
across the push backend, and provides traced topic-subscription
helpers.

```dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:otel_firebase_messaging/otel_firebase_messaging.dart';

// Foreground messages
final fgSub = listenForegroundTraced((message) async {
  // Your foreground handler; runs inside a CONSUMER span.
});

// Tap-to-open messages
final openSub = listenOpenedAppTraced((message) async {
  // Your tap-handler; runs inside a CONSUMER span.
});

// Cold-start: app launched by tapping a notification while terminated
await handleInitialMessageTraced((message) async {
  // ...
});

// Topic management
await FirebaseMessaging.instance.tracedSubscribeToTopic('news');
await FirebaseMessaging.instance.tracedUnsubscribeFromTopic('news');
```

If you have a custom handling pipeline (deduplication, async work
queue), use the underlying helper directly:

```dart
FirebaseMessaging.onMessage.listen((message) async {
  await tracedMessageHandler(
    message,
    handlerType: FcmHandlerType.onMessage,
    handler: (m) => myDispatcher.handle(m),
    topic: 'news',
  );
});
```

## End-to-end trace propagation

If your backend (Cloud Function, server, whatever fans out the
push) injects `traceparent` (and optionally `tracestate`) into the
**`data` payload** of the FCM message, the receive-side span on
the device will stitch into that upstream trace:

```js
// Backend (Cloud Function) — example
admin.messaging().send({
  token: deviceToken,
  data: {
    traceparent: span.spanContext.traceparent,  // W3C format
    payload: '...',
  },
});
```

Now in your trace UI the device-side `firebase_messaging receive`
span appears as a child of the backend span that triggered the
push.

## Span shape

### Receive (CONSUMER)

- **Span name**: `firebase_messaging receive <from>`
- **Span kind**: `CONSUMER`
- **Attributes**:
  - `messaging.system = fcm`
  - `messaging.operation = receive`
  - `messaging.message.id` — `RemoteMessage.messageId`
  - `messaging.destination.name` — the topic, when known
  - `messaging.fcm.from` / `.sender_id` / `.collapse_key`
  - `messaging.fcm.has_notification` — `notification` payload present?
  - `messaging.fcm.content_available` — APNs/FCM background-data flag
  - `messaging.fcm.handler_type` — `on_message` /
    `on_message_opened_app` / `initial_message` / `background`

### Topic management (PRODUCER)

- `firebase_messaging subscribe <topic>` —
  `messaging.operation=subscribe`
- `firebase_messaging unsubscribe <topic>` —
  `messaging.operation=unsubscribe`

## Self-recursion guard

```dart
await runWithoutFirebaseMessagingInstrumentationAsync(() async {
  await FirebaseMessaging.instance.tracedSubscribeToTopic('news');
});
```

## Caveats

- **Background isolate**: messages handled by
  `FirebaseMessaging.onBackgroundMessage` run in a separate
  isolate. `OTel.initialize()` must be called inside that
  isolate's handler before `tracedMessageHandler` will emit
  anything. The `FcmHandlerType.background` value exists for
  you to pass through if you wire that up yourself.
- The `listenForegroundTraced` / `listenOpenedAppTraced` helpers
  use `unawaited(...)` on the per-message span so back-pressure
  on the listener stream isn't affected by handler durations.
  If you need ordered processing, build your own loop around
  `tracedMessageHandler`.
- The wrapper calls `OTel.tracerProvider().getTracer(...)` on each
  invocation — `OTel.initialize()` must have run first.

## License

Apache 2.0 — see `LICENSE`.
