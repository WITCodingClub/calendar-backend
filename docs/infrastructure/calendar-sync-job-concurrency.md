# Calendar Sync Job Concurrency Control

## Overview

This document describes the concurrency control mechanism implemented for `GoogleCalendarSyncJob` to prevent duplicate calendar events when multiple sync operations are triggered simultaneously for the same user.

## Problem Statement

### Initial Issue: Missing Calendar Events

**Symptom:** New users had Google Calendars created but no events were synced to them.

**Root Cause:** The calendar sync job was never triggered during the initial calendar creation flow.

**Fix Location:** `app/services/google_calendar_service.rb:38-40`

When a new Google Calendar is created for a user, the service now automatically triggers an initial sync:

```ruby
# Trigger initial sync for newly created calendars
if newly_created && user.enrollments.any?
  GoogleCalendarSyncJob.perform_later(user, force: true)
end
```

### Secondary Issue: Duplicate Calendar Events

**Symptom:** Some users (specifically Calculus 1B course) had duplicate calendar events - each meeting time had 2 identical events instead of 1.

**Root Cause:** Race condition caused by multiple sync jobs running concurrently:

1. **First trigger:** `GoogleCalendarService#create_or_get_course_calendar` (line 39) - when calendar is created
2. **Second trigger:** `CourseProcessorService#call` (line 133) - when courses are processed

Both jobs ran simultaneously (overlapping execution times), and each created the same set of events because:
- Job 1 started at 23:07:59, finished at 23:08:05
- Job 2 started at 23:08:03 (while Job 1 was still running)
- Both jobs saw empty calendar and created all events
- Result: Duplicate events for meeting times processed by both jobs

## Solution: Concurrency Keys

### Implementation

The solution uses Solid Queue's built-in concurrency control mechanism via concurrency keys.

**File:** `app/jobs/google_calendar_sync_job.rb`

```ruby
class GoogleCalendarSyncJob < ApplicationJob
  queue_as :high

  # Use concurrency keys to prevent multiple sync jobs for the same user
  # Only one job with the same concurrency key will run at a time
  limits_concurrency to: 1, key: ->(user, force: false) { "google_calendar_sync_user_#{user.id}" }

  def perform(user, force: false)
    user.sync_course_schedule(force: force)
  end
end
```

### How It Works

1. **Concurrency Key Generation:**
   - Each job gets a unique key based on user ID: `google_calendar_sync_user_{user_id}`
   - All sync jobs for the same user share the same concurrency key
   - Jobs for different users have different keys and can run in parallel

2. **Concurrency Limit:**
   - Limit is set to `1` per concurrency key
   - Only one job with a given concurrency key can run at a time

3. **Job Queueing Behavior:**
   - **First job:** Goes to `solid_queue_ready_executions` table → runs immediately
   - **Additional jobs:** Go to `solid_queue_blocked_executions` table → wait for first job to complete
   - **Automatic unblocking:** When first job finishes, next blocked job automatically moves to ready state

4. **Database Tables:**
   - `solid_queue_jobs` - All enqueued jobs with their `concurrency_key` column populated
   - `solid_queue_ready_executions` - Jobs ready to run now
   - `solid_queue_blocked_executions` - Jobs waiting due to concurrency limits
   - `solid_queue_semaphores` - Tracks concurrency limits and current usage

### Example Scenario

When 3 sync jobs are enqueued for the same user simultaneously:

```ruby
user = User.find(123)

job1 = GoogleCalendarSyncJob.perform_later(user, force: false)
job2 = GoogleCalendarSyncJob.perform_later(user, force: false)
job3 = GoogleCalendarSyncJob.perform_later(user, force: false)
```

**Result:**

| Job | Concurrency Key | Status | Table |
|-----|----------------|--------|-------|
| Job 1 | `GoogleCalendarSyncJob/google_calendar_sync_user_123` | Ready (running) | `solid_queue_ready_executions` |
| Job 2 | `GoogleCalendarSyncJob/google_calendar_sync_user_123` | Blocked (waiting) | `solid_queue_blocked_executions` |
| Job 3 | `GoogleCalendarSyncJob/google_calendar_sync_user_123` | Blocked (waiting) | `solid_queue_blocked_executions` |

**Execution Order:**
1. Job 1 runs to completion
2. Job 2 automatically unblocks and runs
3. Job 3 automatically unblocks and runs

### Benefits

1. **Prevents Duplicate Events:**
   - Only one sync job per user can run at a time
   - Subsequent jobs see updated database state from previous job

2. **No Race Conditions:**
   - Jobs execute sequentially per user
   - Database state is consistent between jobs

3. **Built-in Queue Management:**
   - Solid Queue handles blocking/unblocking automatically
   - No manual polling or checking required

4. **Cross-User Parallelism:**
   - Jobs for different users can still run in parallel
   - Only per-user operations are serialized

5. **Idiomatic & Maintainable:**
   - Uses Solid Queue's native concurrency control
   - Declarative configuration via `limits_concurrency`
   - No complex manual locking code

## Sync Trigger Points

The calendar sync job can be triggered from multiple locations:

1. **Initial Calendar Creation** (app/services/google_calendar_service.rb:39)
   ```ruby
   GoogleCalendarSyncJob.perform_later(user, force: true)
   ```

2. **Course Processing** (app/services/course_processor_service.rb:133)
   ```ruby
   GoogleCalendarSyncJob.perform_later(user, force: false)
   ```

3. **User Extension Config Changes** (app/models/user_extension_config.rb:37)
   ```ruby
   GoogleCalendarSyncJob.perform_later(user, force: true)
   ```

4. **Calendar Preferences Update** (app/controllers/api/calendar_preferences_controller.rb)
   ```ruby
   GoogleCalendarSyncJob.perform_later(current_user, force: true)
   ```

5. **Manual Trigger** (via console or rake task)
   ```ruby
   GoogleCalendarSyncJob.perform_now(user, force: true)
   ```

All these trigger points are now safe from creating duplicate events due to concurrency control.

## Testing Concurrency Control

### Manual Testing

```ruby
user = User.find(123)

# Clear any existing jobs
SolidQueue::Job.where(class_name: "GoogleCalendarSyncJob").delete_all

# Enqueue multiple jobs
job1 = GoogleCalendarSyncJob.perform_later(user, force: false)
job2 = GoogleCalendarSyncJob.perform_later(user, force: false)
job3 = GoogleCalendarSyncJob.perform_later(user, force: false)

# Verify concurrency keys
jobs = SolidQueue::Job.where(class_name: "GoogleCalendarSyncJob")
jobs.pluck(:id, :concurrency_key)
# => All jobs should have the same concurrency_key

# Check execution state
ready = SolidQueue::ReadyExecution.joins(:job)
  .where(solid_queue_jobs: { class_name: "GoogleCalendarSyncJob" })
  .count
# => Should be 1

blocked = SolidQueue::BlockedExecution.joins(:job)
  .where(solid_queue_jobs: { class_name: "GoogleCalendarSyncJob" })
  .count
# => Should be 2
```

### RSpec Testing

```ruby
RSpec.describe GoogleCalendarSyncJob do
  describe 'concurrency control' do
    let(:user) { create(:user) }

    it 'uses concurrency keys based on user ID' do
      job = described_class.new(user, force: false)

      # Access the concurrency key via perform_later
      job_instance = described_class.perform_later(user, force: false)
      solid_queue_job = SolidQueue::Job.find_by(
        active_job_id: job_instance.job_id
      )

      expect(solid_queue_job.concurrency_key).to eq(
        "GoogleCalendarSyncJob/google_calendar_sync_user_#{user.id}"
      )
    end

    it 'limits concurrency to 1 per user' do
      # Enqueue 3 jobs
      3.times { described_class.perform_later(user, force: false) }

      # Only 1 should be ready
      ready_count = SolidQueue::ReadyExecution.joins(:job)
        .where(solid_queue_jobs: { class_name: described_class.name })
        .count
      expect(ready_count).to eq(1)

      # Others should be blocked
      blocked_count = SolidQueue::BlockedExecution.joins(:job)
        .where(solid_queue_jobs: { class_name: described_class.name })
        .count
      expect(blocked_count).to eq(2)
    end
  end
end
```

## Monitoring

### Checking for Blocked Jobs

```ruby
# Find all blocked sync jobs
blocked = SolidQueue::BlockedExecution.joins(:job)
  .where(solid_queue_jobs: { class_name: "GoogleCalendarSyncJob" })
  .includes(:job)

blocked.each do |execution|
  job = execution.job
  user_id = job.arguments.first["_aj_globalid"].split("/").last
  puts "User #{user_id}: Waiting since #{execution.created_at}"
end
```

### Checking for Long-Running Jobs

```ruby
# Find sync jobs running for more than 5 minutes
long_running = SolidQueue::Job
  .where(class_name: "GoogleCalendarSyncJob")
  .where(finished_at: nil)
  .where("created_at < ?", 5.minutes.ago)

long_running.each do |job|
  user_id = job.arguments.first["_aj_globalid"].split("/").last
  duration = (Time.current - job.created_at).to_i
  puts "User #{user_id}: Running for #{duration}s"
end
```

### Metrics

Track these metrics in production:

- Number of blocked sync jobs per user
- Average wait time for blocked jobs
- Maximum wait time for blocked jobs
- Jobs that timeout or fail due to long waits

## Troubleshooting

### Jobs stuck in blocked state

**Symptom:** Jobs remain in `solid_queue_blocked_executions` indefinitely

**Possible Causes:**
1. First job crashed without finishing
2. Semaphore not released properly
3. Worker process died mid-job

**Solution:**
```ruby
# Find stuck semaphores
SolidQueue::Semaphore.where("expires_at < ?", Time.current)

# Clear stuck semaphores
SolidQueue::Semaphore.where(key: "GoogleCalendarSyncJob/google_calendar_sync_user_123").delete_all

# Manually unblock jobs
stuck_job_id = 456
SolidQueue::BlockedExecution.find_by(job_id: stuck_job_id)&.destroy
SolidQueue::ReadyExecution.create!(job_id: stuck_job_id, queue_name: 'high', priority: 0)
```

### Multiple jobs still creating duplicates

**Symptom:** Despite concurrency control, duplicate events are created

**Diagnostic Steps:**
1. Check if concurrency key is being set:
   ```ruby
   job = SolidQueue::Job.find(123)
   puts job.concurrency_key
   # Should be: "GoogleCalendarSyncJob/google_calendar_sync_user_{id}"
   ```

2. Verify only one job is in ready state:
   ```ruby
   SolidQueue::ReadyExecution.joins(:job)
     .where(solid_queue_jobs: { class_name: "GoogleCalendarSyncJob" })
     .count
   # Should be <= number of unique users
   ```

3. Check if jobs are being created with correct user:
   ```ruby
   jobs = SolidQueue::Job.where(class_name: "GoogleCalendarSyncJob")
   jobs.map { |j| j.arguments.dig("arguments", 0, "_aj_globalid") }
   ```

## Related Documentation

- [Job Queue Priority Configuration](job-queues.md)
- [Intelligent Calendar Sync](../calendar-sync/intelligent_calendar_sync.md)
- [Multi-Email Google Calendar OAuth](../calendar-sync/multi-email-google-calendar-oauth.md)
- [Optimization Metrics](optimization-metrics.md)

## Version History

- **2025-11-10:** Initial documentation of concurrency control implementation
  - Added automatic initial sync trigger
  - Implemented concurrency keys to prevent duplicate events
