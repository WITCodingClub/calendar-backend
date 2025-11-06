# User Google Calendar Edit Detection

## Overview

This feature allows users to edit their course calendar events directly in Google Calendar. When the sync runs, it detects user edits and preserves them instead of overwriting with system data.

## How It Works

### Sync Flow

1. **Trigger**: Sync is initiated (manually or via scheduled job)
2. **Build Events**: System builds event data from current course enrollments
3. **For Each Event**:
   - Check if event data has changed (using hash comparison)
   - If no changes detected → skip (mark as synced)
   - If changes detected → proceed to update

### User Edit Detection

Before updating any event, the system:

1. **Fetches** the current event from Google Calendar
2. **Compares** Google Calendar data with local database:
   - Summary (course title)
   - Location (building + room)
   - Start time
   - End time
   - Recurrence rules

3. **If differences found**:
   - User edited the event in Google Calendar
   - Update local DB with Google Calendar data
   - Skip pushing system update
   - Mark event as synced

4. **If no differences**:
   - No user edits detected
   - Push system update to Google Calendar
   - Update local DB with system data
   - Mark event as synced

## Priority Rules

**User edits always take priority over system updates.**

If a user edits an event in Google Calendar:
- All their changes are preserved
- System updates are NOT applied
- Local database is updated to match Google Calendar

This means if a user changes a course title from "CS 101" to "Intro to CS" in Google Calendar, that custom title will be preserved even if the course data changes in the system.

## Fields That Are Monitored

The following event fields are monitored for user edits:
- **Summary**: Course title
- **Location**: Building and room information
- **Start Time**: When the event starts
- **End Time**: When the event ends
- **Recurrence**: Repeat rules (weekly pattern, end date)

## Implementation Details

### Key Methods

- `user_edited_event?(db_event, gcal_event)`: Detects if user made changes
- `update_db_from_gcal_event(db_event, gcal_event)`: Updates local DB with Google Calendar data
- `parse_gcal_time(time_obj)`: Parses Google Calendar time objects
- `normalize_recurrence(recurrence)`: Normalizes recurrence arrays for comparison

### Database Fields

- `event_data_hash`: SHA256 hash of event data for quick change detection
- `last_synced_at`: Timestamp of last sync

## Edge Cases

### Event Not Found in Google Calendar
If an event doesn't exist in Google Calendar (404 error):
- The local database record is destroyed
- A new event is created in Google Calendar

### Partial User Edits
If a user only edits one field (e.g., just the title):
- All user changes are preserved
- System updates are not applied
- This prevents partial overwrites

## Testing

Comprehensive tests cover:
- User editing each field individually
- Multiple fields edited together
- No user edits (normal system update)
- Event not found scenarios
- Time zone handling
- Recurrence rule comparison

See `spec/services/google_calendar_service_spec.rb` for detailed test cases.
