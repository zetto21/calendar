import 'dart:io';

import '../models/calendar_event.dart';
import '../native/eventkit.dart';
import '../storage/event_store.dart';

/// Mirrors calendar_app/lib/useSystemEvents.ios.ts: on iOS, re-fetch EventKit
/// events in the visible range and merge native edits (title/time/location
/// changes made in the Apple Calendar app) back into events the app created
/// and linked via systemEventId. A no-op on every other platform.
class SystemEventsSync {
  final EventStore store;
  SystemEventsSync(this.store);

  bool get isSupported => Platform.isIOS;

  Future<void> sync(DateTime rangeFrom, DateTime rangeTo) async {
    if (!isSupported) return;
    final available = await EventKit.isAvailable();
    if (!available) return;
    final native = await EventKit.fetchEvents(rangeFrom, rangeTo);
    if (native.isEmpty) return;
    final byId = {for (final e in native) e.systemEventId: e};

    final next = <String, List<CalendarEvent>>{};
    var changed = false;
    for (final entry in store.events.entries) {
      final updated = <CalendarEvent>[];
      for (final event in entry.value) {
        final linkedId = event.systemEventId;
        final match = linkedId != null ? byId[linkedId] : null;
        if (match == null) {
          updated.add(event);
          continue;
        }
        final nativeModified = DateTime.tryParse(match.updatedAt ?? '');
        final localModified = DateTime.tryParse(event.updatedAt ?? '');
        // An older Apple Calendar copy must not undo a newer cloud edit.
        if (localModified != null &&
            (nativeModified == null ||
                !nativeModified.isAfter(localModified))) {
          updated.add(event);
          continue;
        }
        final fieldsChanged =
            match.title != event.title ||
            match.location != event.location ||
            match.description != event.description ||
            match.url != event.url ||
            match.date != event.date ||
            match.time != event.time ||
            match.duration != event.duration;
        if (!fieldsChanged) {
          updated.add(event);
          continue;
        }
        changed = true;
        final merged = event.copyWith(
          title: match.title,
          location: match.location,
          description: match.description,
          url: match.url,
          date: match.date,
          time: match.time,
          clearTime: match.time == null,
          duration: match.duration,
          startsAt: match.startsAt,
          endsAt: match.endsAt,
        );
        if (merged.date != event.date) {
          next.putIfAbsent(merged.date, () => []).add(merged);
        } else {
          updated.add(merged);
        }
      }
      next.putIfAbsent(entry.key, () => []).addAll(updated);
    }
    if (changed) {
      await store.replaceAll(next);
    }
  }
}
