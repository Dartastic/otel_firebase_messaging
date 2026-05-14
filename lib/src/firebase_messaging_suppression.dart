// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'dart:async';

const Symbol _suppressKey = #otel_firebase_messaging_suppress;

bool firebaseMessagingInstrumentationSuppressed() {
  return Zone.current[_suppressKey] == true;
}

T runWithoutFirebaseMessagingInstrumentation<T>(T Function() body) {
  return runZoned(body, zoneValues: {_suppressKey: true});
}

Future<T> runWithoutFirebaseMessagingInstrumentationAsync<T>(
  Future<T> Function() body,
) {
  return runZoned(body, zoneValues: {_suppressKey: true});
}
