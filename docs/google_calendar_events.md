# Google Calendar Events Model

## Overview

The `GoogleCalendarEvent` model stores references to events created in Google Calendar, enabling intelligent event management and efficient synchronization.

## Purpose

Before this model, the calendar sync process would:
1. Delete ALL existing events from Google Calendar
2. Recreate ALL events from scratch

This was inefficient and could cause issues with event tracking and user experience.

With the `GoogleCalendarEvent` model, the sync process now:
1. **Updates** existing events when data changes
2. **Creates** only new events that don't exist yet
3. **Deletes** only events that are no longer needed

## Schema

```ruby
# Table: google_calendar_events
create_table :google_calendar_events do |t|
  t.references :user, null: false, foreign_key: true
  t.references :meeting_time, null: true, foreign_key: true
  t.string :google_event_id, null: false       # The unique ID from Google Calendar
  t.string :calendar_id, null: false           # The calendar where this event lives
  t.string :summary                            # Event title
  t.string :location                           # Event location
  t.datetime :start_time                       # Event start
  t.datetime :end_time                         # Event end
  t.text :recurrence                           # Recurrence rules (JSON array)
  t.timestamps
end
```

### Key Fields

- **google_event_id**: The unique identifier assigned by Google Calendar when the event is created. This is crucial for updating and deleting specific events.
- **calendar_id**: The Google Calendar ID where this event exists (e.g., the user's course calendar)
- **meeting_time_id**: Optional reference to the MeetingTime that generated this event. Null for custom events.
- **recurrence**: Stored as JSON array, contains RRULE strings for recurring events

### Indexes

- `google_event_id` - Fast lookup of events by Google's ID
- `[user_id, calendar_id]` - Fast lookup of all events for a user's calendar
- `[user_id, meeting_time_id]` - Unique constraint ensuring one event per meeting time per user

## Usage

### Automatic Syncing

The model is used automatically when you call:

```ruby
user.sync_course_schedule
```

This will:
1. Build events from the user's enrollments
2. Compare with existing `GoogleCalendarEvent` records
3. Update/create/delete as needed in both Google Calendar and the database

### Manual Queries

Find all events for a user's calendar:

```ruby
user.google_calendar_events.for_calendar(calendar_id)
```

Find events for a specific meeting time:

```ruby
GoogleCalendarEvent.for_meeting_time(meeting_time_id)
```

Get the Google Calendar event ID:

```ruby
event = user.google_calendar_events.first
event.google_event_id  # => "abc123xyz456"
```

### Update Flow

When `sync_course_schedule` is called:

1. **Fetch existing events** from database
   ```ruby
   existing_events = user.google_calendar_events.for_calendar(calendar_id)
   ```

2. **For each course event**:
   - If exists: Update if data changed
   - If not: Create new event and save to database

3. **Delete orphaned events**:
   - Events in database but not in current schedule are removed

### Error Handling

The service includes automatic recovery for common issues:

- **404 Not Found**: If an event doesn't exist in Google Calendar but is in the database, it will be recreated
- **Stale data**: If the database has an event that was deleted from Google Calendar, the sync will handle it gracefully

## Benefits

1. **Efficiency**: Only changed events are updated
2. **Speed**: Significantly faster syncs after the initial creation
3. **Reliability**: Better tracking of event state
4. **Debugging**: Easy to see what events exist and their IDs
5. **Future features**: Enables advanced features like:
   - Event-specific metadata
   - Custom event tracking
   - Analytics on calendar usage
   - Partial syncs

## Development Notes

### Creating a GoogleCalendarEvent

Events are created automatically during sync, but you can also create them manually:

```ruby
GoogleCalendarEvent.create!(
  user: user,
  meeting_time: meeting_time,
  google_event_id: "abc123",
  calendar_id: user.google_course_calendar_id,
  summary: "Computer Science I",
  location: "Wentworth Hall - 306",
  start_time: Time.zone.now,
  end_time: Time.zone.now + 1.hour,
  recurrence: ["RRULE:FREQ=WEEKLY;BYDAY=MO"]
)
```

### Cleaning Up

When deleting a calendar, all associated events are automatically cleaned up:

```ruby
user.delete_course_calendar
# This deletes both the calendar in Google and all GoogleCalendarEvent records
```

## Migration

After adding this model, existing calendars will be empty in the database. The first sync will populate them:

```ruby
User.find_each do |user|
  user.sync_course_schedule if user.google_course_calendar_id.present?
end
```

## Testing

Run the Rails console to test:

```ruby
user = User.first

# Initial sync - creates events
user.sync_course_schedule
puts "Created #{user.google_calendar_events.count} events"

# Second sync - should NOT recreate events
initial_ids = user.google_calendar_events.pluck(:google_event_id)
user.sync_course_schedule
final_ids = user.google_calendar_events.pluck(:google_event_id)

puts "Events were #{'updated' if initial_ids == final_ids else 'recreated'}"
```

## Future Enhancements

Possible improvements:
- Add `last_synced_at` timestamp
- Track sync errors per event
- Add event metadata (color preferences, custom descriptions)
- Support for custom user-created events
- Event history tracking
