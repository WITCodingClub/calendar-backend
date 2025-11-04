# Job Queue Priority Configuration

## Overview

The application uses Solid Queue as the Active Job backend with multiple priority queues to ensure critical user-facing operations are processed quickly while background tasks don't impact user experience.

## Queue Configuration

The application uses three priority queues configured in `config/queue.yml`:

### 1. High Priority Queue (`high_priority`)
- **Threads:** 3
- **Polling Interval:** 0.1 seconds
- **Purpose:** User-facing operations that should complete as quickly as possible
- **Jobs:**
  - `GoogleCalendarCreateJob` - Creating Google Calendar for users
  - `GoogleCalendarSyncJob` - Syncing course schedule to Google Calendar
  - `GoogleCalendarDeleteJob` - Deleting Google Calendar when user disconnects
  - `CourseProcessorJob` - Processing course data when user uploads

### 2. Default Queue (`default`)
- **Threads:** 2
- **Polling Interval:** 0.5 seconds
- **Purpose:** Standard priority jobs that don't require immediate processing
- **Jobs:** Currently reserved for future use

### 3. Low Priority Queue (`low_priority`)
- **Threads:** 1
- **Polling Interval:** 1 second
- **Purpose:** Background batch operations and scheduled tasks
- **Jobs:**
  - `NightlyCalendarSyncJob` - Nightly batch sync of user calendars (scheduled at 3:30 AM)
  - `UpdateFacultyRatingsJob` - Fetching Rate My Professor data (scheduled weekly on Sundays at 3:00 AM)

## How It Works

### Worker Configuration

Each queue has its own worker pool with different resource allocations:

- **High Priority:** More threads (3) and faster polling (0.1s) ensures quick response times
- **Default:** Moderate threads (2) and polling (0.5s) for standard operations
- **Low Priority:** Fewer threads (1) and slower polling (1s) to avoid consuming resources needed for user-facing tasks

### Concurrency

The number of worker processes for each queue is controlled by the `JOB_CONCURRENCY` environment variable (defaults to 1). This can be increased in production for higher throughput.

## Assigning Jobs to Queues

When creating a new job, specify the appropriate queue based on its characteristics:

```ruby
class MyJob < ApplicationJob
  queue_as :high_priority  # For user-facing operations
  # or
  queue_as :default        # For standard operations
  # or
  queue_as :low_priority   # For background/batch operations
end
```

### Guidelines for Queue Selection

Choose **high_priority** if:
- The job is triggered by a user action
- The user is waiting for the job to complete
- Fast response time is critical to user experience

Choose **default** if:
- The job doesn't fit high or low priority criteria
- Response time is important but not critical

Choose **low_priority** if:
- The job is a scheduled/recurring task
- The job processes data in batches
- The job can run during off-peak hours
- Response time is not critical

## Scheduled Jobs

Recurring jobs configured in `config/recurring.yml` should explicitly specify their queue:

```yaml
my_nightly_job:
  class: MyNightlyJob
  queue: low_priority  # Explicitly assign to low_priority
  schedule: every day at 3am
```

## Monitoring

Monitor queue health and job performance through:

1. **Mission Control Jobs** - View job status, queues, and execution history
2. **Rails Logs** - Check for job execution logs and errors
3. **Database Queries** - Inspect `solid_queue_*` tables for queue metrics

### Useful Queries

```ruby
# Check jobs by queue
SolidQueue::Job.where(queue_name: 'high_priority')

# Check pending jobs
SolidQueue::Job.where(finished_at: nil)

# Check failed jobs
SolidQueue::FailedExecution.all
```

## Performance Considerations

### Resource Allocation

The current configuration assumes:
- High priority jobs complete quickly (seconds)
- Low priority jobs may take longer (minutes)
- Total concurrent jobs = 3 (high) + 2 (default) + 1 (low) = 6 jobs per process

### Scaling

To handle higher load:

1. **Increase JOB_CONCURRENCY:**
   ```bash
   JOB_CONCURRENCY=2  # Runs 2 processes per queue
   ```

2. **Adjust thread counts in queue.yml:**
   ```yaml
   - queues: high_priority
     threads: 5  # Increase from 3
   ```

3. **Add more queue workers:**
   - Deploy dedicated worker instances
   - Configure different workers for different queues

## Testing

All job specs include queue assignment tests:

```ruby
describe 'queue assignment' do
  it 'is assigned to the high_priority queue' do
    expect(described_class.new.queue_name).to eq('high_priority')
  end
end
```

Run queue-specific tests:

```bash
# Test all jobs
bundle exec rspec spec/jobs/

# Test specific job
bundle exec rspec spec/jobs/google_calendar_create_job_spec.rb
```

## Troubleshooting

### Jobs not processing

1. Check if Solid Queue workers are running:
   ```bash
   bin/rails solid_queue:start
   ```

2. Verify queue configuration in `config/queue.yml`

3. Check logs for errors:
   ```bash
   tail -f log/development.log
   ```

### Queue backlog

If a queue has too many pending jobs:

1. Check if workers are running
2. Increase JOB_CONCURRENCY for that queue
3. Add more threads to the queue worker
4. Consider moving some jobs to a lower priority queue

### Jobs timing out

1. Increase job timeout in the job class:
   ```ruby
   class MyJob < ApplicationJob
     queue_as :low_priority
     
     # Set custom timeout (default is 600 seconds)
     retry_on Timeout::Error, wait: 5.seconds, attempts: 3
   end
   ```

2. Consider breaking large jobs into smaller batches

## Future Improvements

Potential enhancements:

- [ ] Add queue-specific metrics/monitoring
- [ ] Implement priority-based job scheduling within queues
- [ ] Add automatic queue selection based on job characteristics
- [ ] Configure separate Redis/database for job queues
- [ ] Add rate limiting for external API jobs
- [ ] Implement circuit breakers for failing jobs
