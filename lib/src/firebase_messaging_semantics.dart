// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry_api/dartastic_opentelemetry_api.dart';

/// FCM-specific messaging attribute keys (a thin extension of the
/// upstream `messaging.*` semconv namespace).
///
/// Also includes the `messaging.operation` / `messaging.message.id`
/// / `messaging.destination.name` keys from the current OTel
/// semconv that aren't yet in the API's `Messaging` enum — once
/// they migrate upstream, those entries can be removed in favor of
/// the API constants.
enum FirebaseMessagingSemantics implements OTelSemantic {
  /// `messaging.operation` — the operation being performed
  /// (`receive`, `subscribe`, `unsubscribe`).
  operation('messaging.operation'),

  /// `messaging.message.id` — the message ID assigned by the
  /// system (current OTel semconv key).
  messageId('messaging.message.id'),

  /// `messaging.destination.name` — the destination (topic) the
  /// message was sent to / received from.
  destinationName('messaging.destination.name'),

  /// `messaging.fcm.from` — the value of `RemoteMessage.from`
  /// (usually `/topics/<topic>` or the sender's FCM project number).
  from('messaging.fcm.from'),

  /// `messaging.fcm.sender_id` — sender ID from
  /// `RemoteMessage.senderId`.
  senderId('messaging.fcm.sender_id'),

  /// `messaging.fcm.collapse_key` — collapse key, used by FCM for
  /// deduplication.
  collapseKey('messaging.fcm.collapse_key'),

  /// `messaging.fcm.has_notification` — `true` when the message
  /// includes a foreground `notification` payload.
  hasNotification('messaging.fcm.has_notification'),

  /// `messaging.fcm.content_available` — APNs/FCM `contentAvailable`
  /// flag.
  contentAvailable('messaging.fcm.content_available'),

  /// `messaging.fcm.handler_type` — `on_message`,
  /// `on_message_opened_app`, `initial_message`, `background`.
  handlerType('messaging.fcm.handler_type');

  @override
  final String key;

  @override
  String toString() => key;

  const FirebaseMessagingSemantics(this.key);
}
