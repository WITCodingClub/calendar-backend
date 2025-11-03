# Nightly Google Calendar Sync

## Overview

This document describes the nightly calendar sync functionality that automatically updates Google Calendar events when course data changes.

## Architecture

### Change Tracking

The system tracks changes to course-related data that affect calendar events:

#### Database Fields (Users table)

- `calendar_needs_sync` (boolean): Flag indicating if the user's calendar needs to be synced
- `last_calendar_sync_at` (datetime): Timestamp of the last successful calendar sync

#### Tracked Changes

The following changes trigger the `calendar_needs_sync` flag to be set to `true`:

1. **Enrollments**
   - New enrollment created
   - Enrollment deleted
   
2. **Courses**
   - Course title changed
   - Course dates changed (start_date, end_date)
   - Course metadata changed (subject, course_number, section_number)
   - Course deleted

3. **Meeting Times**
   - Meeting time changed (begin_time, end_time)
   - Meeting day changed (day_of_week)
   - Meeting dates changed (start_date, end_date)
   - Room changed
   - Meeting time deleted

### Nightly Sync Job

#### Job Configuration

The `NightlyCalendarSyncJob` runs at **3:30 AM daily** (configured in `config/recurring.yml`):

```yaml
nightly_calendar_sync:
  class: NightlyCalendarSyncJob
  schedule: every day at 3:30am
```

#### Job Behavior

The job performs the following steps:

1. **Find Users to Sync**: Queries for users who:
   - Have `calendar_needs_sync = true`, OR
   - Have never been synced (`last_calendar_sync_at IS NULL`)
   - AND have a Google Calendar configured (`google_course_calendar_id` is present)

2. **Sync Each User**: For each user:
   - Calls `user.sync_course_schedule` to update Google Calendar events
   - Updates `calendar_needs_sync = false`
   - Updates `last_calendar_sync_at = current_time`
   - Continues to next user if sync fails (errors are logged but don't stop the job)

3. **Logging**: The job logs:
   - Total number of users to sync
   - Success/failure for each user sync
   - Full error details when syncs fail

#### Manual Trigger

You can manually trigger the nightly sync job for testing:

```ruby
# In Rails console
NightlyCalendarSyncJob.perform_now
```

## Implementation Details

### Concerns

Three ActiveSupport concerns handle change tracking:

1. **`CalendarSyncable`** (included in `Enrollment`)
   - Marks user's calendar for sync after enrollment save/destroy

2. **`CourseChangeTrackable`** (included in `Course`)
   - Marks all enrolled users' calendars for sync when relevant course fields change

3. **`MeetingTimeChangeTrackable`** (included in `MeetingTime`)
   - Marks all enrolled users' calendars for sync when relevant meeting time fields change

### Sync Process

When `sync_course_schedule` is called (defined in `CourseScheduleSyncable` concern):

1. Builds event data from all enrollments and their associated courses/meeting times
2. Calls `GoogleCalendarService#update_calendar_events`
3. Clears existing events from the calendar
4. Creates new events with current data

## Testing

Tests are provided for:

- `NightlyCalendarSyncJob` behavior
- `Enrollment` change tracking
- `Course` change tracking
- `MeetingTime` change tracking

Run tests with:

```bash
bundle exec rspec spec/jobs/nightly_calendar_sync_job_spec.rb
bundle exec rspec spec/models/enrollment_spec.rb
bundle exec rspec spec/models/course_spec.rb
bundle exec rspec spec/models/meeting_time_spec.rb
```

## Monitoring

Monitor the nightly sync job through:

1. **Rails Logs**: Check for sync start/completion and any errors
2. **Mission Control Jobs**: View job status and history
3. **Database Queries**: Check users with `calendar_needs_sync = true`

## Troubleshooting

### User calendar not syncing

1. Check if user has `google_course_calendar_id` set
2. Verify `calendar_needs_sync` flag is set to `true`
3. Check job logs for errors during sync
4. Manually trigger sync for specific user:
   ```ruby
   user = User.find(user_id)
   user.sync_course_schedule
   ```

### Sync failures

Common issues:

- **OAuth token expired**: User needs to re-authenticate
- **Calendar not found**: The calendar may have been deleted manually
- **API rate limits**: Google Calendar API may be rate limiting requests

### Manual sync for all users

```ruby
User.where.not(google_course_calendar_id: nil).find_each do |user|
  user.update_column(:calendar_needs_sync, true)
end
NightlyCalendarSyncJob.perform_now
```
