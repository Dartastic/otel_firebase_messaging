// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

/// OpenTelemetry instrumentation for `package:firebase_messaging`.
///
/// Wraps incoming `RemoteMessage` handlers in CONSUMER spans, extracts
/// W3C trace context from `message.data` for end-to-end propagation,
/// and provides traced topic-subscription helpers.
library;

export 'src/firebase_messaging_semantics.dart';
export 'src/firebase_messaging_suppression.dart';
export 'src/otel_firebase_messaging.dart';
