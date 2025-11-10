# Optimization Metrics & Logging

This document describes the StatsD metrics and structured logging added to track the effectiveness of background job optimizations.

## Overview

The calendar sync system employs multiple optimization strategies to reduce unnecessary API calls:
- **Timestamp comparison** - Skip jobs when no data has changed
- **Hash-based change detection** - Skip event updates when content is identical
- **User edit detection** - Preserve user modifications in Google Calendar
- **Freshness caching** - Skip API calls when data is recent

This metrics system tracks when these optimizations trigger, allowing you to measure their effectiveness.

## StatsD Configuration

StatsD is configured in `config/initializers/statsd.rb`:
- **Environment**: `production`
- **Address**: `telemetry.hogwarts.dev:8125`
- **Prefix**: `witccdotdev.server.#{Rails.env}`

All metrics are automatically prefixed with this namespace.

## Background Job Metrics

### GoogleCalendarSyncJob

**Purpose**: Tracks when the entire calendar sync job is skipped vs. executed.

#### Metrics

```ruby
# Job skipped due to no course changes
StatsD.increment("jobs.google_calendar_sync.skipped",
  tags: ["reason:no_course_changes", "user_id:#{user.id}"])

# Job executed
StatsD.increment("jobs.google_calendar_sync.executed",
  tags: ["reason:course_changes_detected", "user_id:#{user.id}"])
# OR
StatsD.increment("jobs.google_calendar_sync.executed",
  tags: ["reason:forced", "user_id:#{user.id}"])
```

#### Structured Logging

**Skip Log:**
```json
{
  "message": "GoogleCalendarSyncJob skipped - no course changes",
  "user_id": 123,
  "last_sync_at": "2025-01-09T12:00:00Z",
  "last_course_update_at": "2025-01-08T10:00:00Z",
  "time_since_sync_seconds": 93600,
  "reason": "no_course_changes"
}
```

**Execution Log:**
```json
{
  "message": "GoogleCalendarSyncJob executing",
  "user_id": 123,
  "force": false,
  "reason": "course_changes_detected"
}
```

#### Analysis Queries

**Calculate skip rate:**
```
skip_rate = jobs.google_calendar_sync.skipped /
            (jobs.google_calendar_sync.skipped + jobs.google_calendar_sync.executed)
```

**Average time between syncs:**
- Parse `time_since_sync_seconds` from logs
- Group by user to find patterns

---

### UpdateFacultyRatingsJob

**Purpose**: Tracks when RateMyProfessor updates are skipped vs. executed.

#### Metrics

```ruby
# Job skipped - ratings recently updated (< 1 week)
StatsD.increment("jobs.update_faculty_ratings.skipped",
  tags: ["reason:recently_updated", "faculty_id:#{faculty.id}"])

# Job skipped - no RMP ID found
StatsD.increment("jobs.update_faculty_ratings.skipped",
  tags: ["reason:no_rmp_id", "faculty_id:#{faculty.id}"])

# Job executed
StatsD.increment("jobs.update_faculty_ratings.executed",
  tags: ["faculty_id:#{faculty.id}"])

# Ratings successfully updated
StatsD.increment("jobs.update_faculty_ratings.ratings_updated",
  tags: ["faculty_id:#{faculty.id}"])

# Count of ratings fetched
StatsD.gauge("jobs.update_faculty_ratings.rating_count", count,
  tags: ["faculty_id:#{faculty.id}"])
```

#### Structured Logging

**Skip Log (Recently Updated):**
```json
{
  "message": "UpdateFacultyRatingsJob skipped - ratings recently updated",
  "faculty_id": 45,
  "faculty_name": "John Smith",
  "last_update_at": "2025-01-03T08:00:00Z",
  "time_since_update_seconds": 518400,
  "reason": "recently_updated"
}
```

**Skip Log (No RMP ID):**
```json
{
  "message": "UpdateFacultyRatingsJob skipped - no RMP ID found",
  "faculty_id": 45,
  "faculty_name": "John Smith",
  "reason": "no_rmp_id"
}
```

**Execution Log:**
```json
{
  "message": "UpdateFacultyRatingsJob executing",
  "faculty_id": 45,
  "faculty_name": "John Smith",
  "rmp_id": "abc123"
}
```

**Completion Log:**
```json
{
  "message": "UpdateFacultyRatingsJob completed",
  "faculty_id": 45,
  "faculty_name": "John Smith",
  "ratings_count": 147
}
```

#### Analysis Queries

**Calculate RMP API call savings:**
```
api_calls_avoided = jobs.update_faculty_ratings.skipped[reason:recently_updated]
```

**Identify faculty missing RMP IDs:**
```
filter: jobs.update_faculty_ratings.skipped[reason:no_rmp_id]
group by: faculty_id
```

---

## Calendar Event Metrics

### Event-Level Operations

**Purpose**: Track individual event operations during sync.

#### Metrics

```ruby
# Event created
StatsD.increment("calendar.sync.event.created",
  tags: ["user_id:#{user.id}"])

# Event updated
StatsD.increment("calendar.sync.event.updated",
  tags: ["user_id:#{user.id}", "forced:#{force}"])

# Event deleted
StatsD.increment("calendar.sync.event.deleted",
  tags: ["user_id:#{user.id}"])

# Event skipped - no data change (hash-based detection)
StatsD.increment("calendar.sync.event.skipped",
  tags: ["reason:no_data_change", "user_id:#{user.id}"])

# Event skipped - user edited in Google Calendar
StatsD.increment("calendar.sync.event.skipped",
  tags: ["reason:user_edit", "user_id:#{user.id}"])
```

#### Structured Logging

**User Edit Skip:**
```json
{
  "message": "Event skipped - user edited in Google Calendar",
  "user_id": 123,
  "google_event_id": "abc123xyz",
  "meeting_time_id": 456,
  "reason": "user_edit"
}
```

**Event Recreation:**
```json
{
  "message": "Event not found in Google Calendar, recreating",
  "user_id": 123,
  "google_event_id": "abc123xyz",
  "meeting_time_id": 456
}
```

**Event Deletion (Already Deleted):**
```json
{
  "message": "Event not found in Google Calendar, removing from database",
  "user_id": 123,
  "google_event_id": "abc123xyz"
}
```

---

### Aggregate Sync Metrics

**Purpose**: Track overall sync performance per job execution.

#### Metrics

```ruby
# Counts per sync job
StatsD.gauge("calendar.sync.events.created", count,
  tags: ["user_id:#{user.id}"])

StatsD.gauge("calendar.sync.events.updated", count,
  tags: ["user_id:#{user.id}"])

StatsD.gauge("calendar.sync.events.skipped", count,
  tags: ["user_id:#{user.id}"])
```

#### Structured Logging

```json
{
  "message": "Calendar sync completed",
  "user_id": 123,
  "events_created": 5,
  "events_updated": 3,
  "events_skipped": 42,
  "total_processed": 50,
  "skip_percentage": 84.0,
  "optimization_effective": true
}
```

#### Analysis Queries

**Calculate optimization effectiveness:**
```
skip_percentage = (events_skipped / total_processed) * 100
```

**Identify users with high update rates (potential issues):**
```
filter: skip_percentage < 20
group by: user_id
```

**Track API call reduction:**
```
api_calls_saved = events_skipped
api_calls_made = events_created + events_updated
savings_rate = (api_calls_saved / (api_calls_saved + api_calls_made)) * 100
```

---

## Monitoring Dashboards

### Recommended Metrics to Graph

1. **Job Skip Rate Over Time**
   - `jobs.google_calendar_sync.skipped` vs `jobs.google_calendar_sync.executed`
   - Shows how often the timestamp optimization works

2. **Event Skip Breakdown**
   - `calendar.sync.event.skipped` by reason tag
   - Pie chart: `no_data_change` vs `user_edit`

3. **API Call Savings**
   - Total events processed vs events skipped
   - Line graph showing savings over time

4. **Faculty Rating Cache Hit Rate**
   - `jobs.update_faculty_ratings.skipped[reason:recently_updated]` vs `jobs.update_faculty_ratings.executed`

5. **Sync Efficiency Per User**
   - `skip_percentage` distribution
   - Histogram showing optimization effectiveness

### Alerts

**Low Skip Rate Alert:**
```
alert: calendar.sync.events.skipped < 50% of total_processed
condition: sustained for > 1 hour
action: Investigate if hash-based detection is working
```

**High Forced Sync Rate:**
```
alert: jobs.google_calendar_sync.executed[reason:forced] > 10% of executions
condition: sustained for > 1 day
action: Check if users are repeatedly forcing syncs (UX issue?)
```

**RMP API Overuse:**
```
alert: jobs.update_faculty_ratings.skipped[reason:recently_updated] < 80%
condition: sustained for > 1 day
action: Verify 1-week cache is working correctly
```

---

## Log Parsing Examples

### Parse Optimization Effectiveness (jq)

**Find average skip percentage:**
```bash
grep "Calendar sync completed" production.log | \
  jq -r '.skip_percentage' | \
  awk '{sum+=$1; count++} END {print sum/count}'
```

**Find users with no optimization benefit:**
```bash
grep "Calendar sync completed" production.log | \
  jq -r 'select(.skip_percentage == 0) | .user_id' | \
  sort | uniq -c
```

**Calculate time saved by job-level skips:**
```bash
grep "GoogleCalendarSyncJob skipped" production.log | \
  jq -r '.time_since_sync_seconds' | \
  awk '{sum+=$1; count++} END {print "Total seconds saved:", sum, "\nAvg skip interval:", sum/count}'
```

---

## Related Documentation

- [Intelligent Calendar Sync](../calendar-sync/intelligent_calendar_sync.md) - Technical details on optimization strategies
- [Job Queues](./job-queues.md) - Background job architecture
- [StatsD Configuration](../../config/initializers/statsd.rb) - Metrics infrastructure

---

## Changelog

**2025-01-09**: Initial metrics implementation
- Added StatsD tracking to GoogleCalendarSyncJob
- Added StatsD tracking to UpdateFacultyRatingsJob
- Added event-level metrics to GoogleCalendarService
- Converted all skip logs to structured JSON format
- Added aggregate sync metrics with skip percentage calculation
