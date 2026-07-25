/// Returns the beginning of the device-local calendar day containing [value].
DateTime startOfLocalCalendarDay(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Returns the beginning of the next device-local calendar day.
///
/// Constructing the next date (instead of adding 24 hours) keeps the boundary
/// correct even in locales that observe daylight-saving time.
DateTime startOfNextLocalCalendarDay(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day + 1);
}

/// Time remaining until the device-local date changes.
Duration durationUntilNextLocalCalendarDay(DateTime value) {
  return startOfNextLocalCalendarDay(value).difference(value.toLocal());
}

/// Whether [value] belongs to the same device-local date as [reference].
bool isOnSameLocalCalendarDay(DateTime value, DateTime reference) {
  final valueLocal = value.toLocal();
  final referenceLocal = reference.toLocal();
  return valueLocal.year == referenceLocal.year &&
      valueLocal.month == referenceLocal.month &&
      valueLocal.day == referenceLocal.day;
}
