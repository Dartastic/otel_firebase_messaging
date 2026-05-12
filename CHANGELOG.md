# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0-wip]

### Added

- `tracedMessageHandler(message, handlerType, handler, topic)` —
  wraps an inbound `RemoteMessage` handler in a CONSUMER span
  named `firebase_messaging receive <from>` with
  `messaging.system=fcm`, `messaging.operation=receive`, and FCM
  metadata (`messaging.fcm.from`, `.sender_id`, `.collapse_key`,
  `.has_notification`, `.content_available`, `.handler_type`).
- W3C trace context extraction from `RemoteMessage.data` —
  servers that inject `traceparent` (and optionally `tracestate`)
  into the FCM payload data get end-to-end traces that stitch
  the device-side span to the backend span that triggered the
  push.
- `listenForegroundTraced` / `listenOpenedAppTraced` — convenience
  subscribers around `FirebaseMessaging.onMessage` /
  `onMessageOpenedApp` that wrap each emission via
  `tracedMessageHandler`. Return the underlying
  `StreamSubscription`.
- `handleInitialMessageTraced` — wraps
  `FirebaseMessaging.instance.getInitialMessage()` for the
  terminated-state launch path.
- `FcmHandlerType` enum — distinguishes `on_message`,
  `on_message_opened_app`, `initial_message`, and `background`
  span sources for trace filtering.
- Extension methods on `FirebaseMessaging`:
  `tracedSubscribeToTopic`, `tracedUnsubscribeFromTopic` —
  PRODUCER spans with `messaging.operation=subscribe` /
  `unsubscribe`.
- `runWithoutFirebaseMessagingInstrumentation` /
  `runWithoutFirebaseMessagingInstrumentationAsync` — zone-scoped
  suppression helpers.
- `FirebaseMessagingSemantics` — typed attribute-key enum
  including the current OTel semconv `messaging.operation`,
  `messaging.message.id`, `messaging.destination.name` keys that
  aren't yet in the API's `Messaging` enum.
- Tests cover the full receive span (all attributes), W3C trace
  context extraction (stitching to an upstream traceId +
  spanId), handler error path, handler-type variants, and the
  suppression scope.
