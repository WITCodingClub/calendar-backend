# Reminder Sync Investigation

**Issue:** [#122](https://github.com/jaspermayone/witcc-calendar-backend/issues/122)
**Date:** 2025-11-09
**Status:** ✅ Fixed - Long-term solution implemented

## Problem Statement

User reports that notifications/reminders are not syncing to Google Calendar events. Screenshot shows empty notification section in Google Calendar event details.

## Investigation Summary

### What I Found

1. **Reminders ARE being applied in the code** ✅
   - `GoogleCalendarService#create_event_in_calendar` (lines 431-459) applies reminders
   - `GoogleCalendarService#update_event_in_calendar` (lines 545-573) applies reminders
   - System defaults include: 30-minute popup notification
   - Tests confirm reminders are being sent to Google Calendar API

2. **However, there's a critical issue with hash-based change detection** ⚠️
   - The `GoogleCalendarEvent.generate_data_hash` method (lines 54-64) does NOT include:
     - `reminder_settings`
     - `color_id`
     - `visibility`
   - This means existing events won't be updated when these preferences change
   - Events created before reminders were fully implemented won't have reminders

3. **User edit detection doesn't check reminders** ⚠️
   - The `user_edited_event?` method only checks: summary, location, times, and recurrence
   - If a user adds reminders in Google Calendar, the system won't detect it
   - If a user removes reminders in Google Calendar, the system might re-add them

4. **Database doesn't store reminder_settings** ⚠️
   - The `google_calendar_events` table doesn't have a column for `reminder_settings`
   - We can't detect if reminders changed without fetching from Google Calendar API

## Root Cause

Events that were created **before the reminder implementation was complete** do not have reminders set, and they won't get updated because:
1. The hash doesn't include reminder_settings
2. Without a hash change, the sync skips the event
3. Only events with other changes (title, time, etc.) would get reminders applied

## Why Reminders Might Not Be Syncing

There are several scenarios:

### Scenario 1: Existing Events (Most Likely)
Events created before full reminder implementation don't have reminders and won't get updated unless:
- Something else changes (title, time, etc.)
- A force sync is triggered with `force: true`

### Scenario 2: Empty Reminder Settings
If the user has a `CalendarPreference` with `reminder_settings: []`, the system still applies defaults. This might be confusing but is working as designed.

### Scenario 3: Invalid Reminder Format
If reminder_settings are somehow malformed, they would be filtered out. But validation prevents this from being saved.

## Solutions

### Immediate Fix: Force Re-sync
Users can force re-sync all events to apply current preferences:
```bash
rails debug:force_sync_reminders[user@example.com]
```

Or via Rails console:
```ruby
user = User.find_by_email("user@example.com")
GoogleCalendarSyncJob.perform_now(user, force: true)
```

### Long-term Fixes

#### Option 1: Include reminders in hash (Recommended)
**Pros:**
- Events will update when reminder preferences change
- Consistent with how we track other event data
- Better change detection

**Cons:**
- Every reminder preference change will trigger updates for ALL events
- More API calls to Google Calendar

**Implementation:**
```ruby
def self.generate_data_hash(event_data)
  hash_input = [
    event_data[:summary],
    event_data[:location],
    event_data[:start_time]&.to_i,
    event_data[:end_time]&.to_i,
    event_data[:recurrence]&.to_json,
    event_data[:reminder_settings]&.to_json,  # Add this
    event_data[:color_id],                     # Add this
    event_data[:visibility]                    # Add this
  ].join("|")

  Digest::SHA256.hexdigest(hash_input)[0..15]
end
```

#### Option 2: Store reminders in database
**Pros:**
- Can detect changes without Google API call
- Can preserve user edits to reminders

**Cons:**
- Schema change required
- Migration complexity
- Need to handle JSON serialization

**Implementation:**
1. Add migration: `add_column :google_calendar_events, :reminder_settings, :jsonb`
2. Update hash generation to include reminders
3. Update `user_edited_event?` to check reminders
4. Update `update_db_from_gcal_event` to save reminders

#### Option 3: Periodic force sync
**Pros:**
- No code changes to hash logic
- Ensures all events eventually get current preferences

**Cons:**
- Wasteful API calls
- Delay in applying preference changes
- Overwrites user edits periodically

## Testing

Created comprehensive test suite in `spec/services/google_calendar_service_reminders_spec.rb`:
- ✅ Default reminders are applied (30-minute popup)
- ✅ Custom reminders from preferences are applied
- ✅ "notification" is normalized to "popup" for Google Calendar API
- ✅ Invalid reminders are filtered out
- ✅ Time conversion (minutes, hours, days) works correctly

## Debugging Tools

Created `lib/tasks/debug_reminders.rake` with two tasks:

1. **Inspect reminder settings:**
   ```bash
   rails debug:reminders[user@example.com]
   ```
   Shows:
   - User's calendar preferences
   - Resolved preferences for a sample event
   - Actual reminders set in Google Calendar

2. **Force re-sync with current preferences:**
   ```bash
   rails debug:force_sync_reminders[user@example.com]
   ```

## Recommendations

1. **Immediate Action:**
   - Run debug task for affected user to confirm diagnosis
   - Force re-sync their events to apply reminders

2. **Short-term Fix:**
   - Include `reminder_settings`, `color_id`, and `visibility` in hash generation
   - This ensures preference changes are applied to all events

3. **Long-term Enhancement:**
   - Consider storing reminders in database
   - Implement reminder edit detection in `user_edited_event?`
   - Add tests for reminder change detection

4. **Documentation:**
   - Update user docs about reminder preferences
   - Explain that preference changes require re-sync for existing events

## Related Files

- `app/services/google_calendar_service.rb:431-459` - Create event with reminders
- `app/services/google_calendar_service.rb:545-573` - Update event with reminders
- `app/services/preference_resolver.rb:17` - System default reminders
- `app/models/google_calendar_event.rb:54-64` - Hash generation (missing reminders!)
- `app/models/concerns/reminder_settings_normalizable.rb` - Reminder validation
- `spec/services/google_calendar_service_reminders_spec.rb` - Reminder tests
- `lib/tasks/debug_reminders.rake` - Debugging tools
