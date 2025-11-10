# Telemetry and Metrics

This document describes the telemetry and metrics system used in the application, powered by StatsD.

## Overview

The application uses [statsd-instrument](https://github.com/Shopify/statsd-instrument) to send metrics to a StatsD server. Metrics are automatically collected for:

- HTTP requests (controllers)
- Background jobs
- Database queries
- Cache operations
- External HTTP API calls
- Google Calendar operations
- View rendering
- Email delivery
- File storage operations

## Configuration

StatsD is configured in `config/initializers/statsd.rb`:

```ruby
ENV["STATSD_ENV"] = "production" # Only sends data in production
ENV["STATSD_ADDR"] = "telemetry.hogwarts.dev:8125"
ENV["STATSD_PREFIX"] = "witccdotdev.server.#{Rails.env}"
```

### Environment Variables

- `STATSD_ENV`: Controls which environments send metrics (default: "production")
- `STATSD_ADDR`: StatsD server address and port
- `STATSD_PREFIX`: Prefix for all metric names (includes Rails environment)

## Metric Types

StatsD supports three main metric types:

1. **Counter** (`increment`): Tracks occurrences of events
2. **Gauge** (`gauge`): Tracks a value at a point in time
3. **Timing** (`measure`): Tracks duration of operations in milliseconds

## Instrumented Components

### 1. Controllers (via `Telemetry` concern)

**Location**: `app/controllers/concerns/telemetry.rb`

Automatically tracks all controller requests via `around_action` hook.

**Metrics**:
- `controller.request.duration` (timing) - Request processing time
- `controller.request.count` (counter) - Number of requests
- `controller.request.error` (counter) - Requests with 4xx/5xx status
- `controller.request.exception` (counter) - Requests that raised exceptions

**Tags**:
- `controller`: Controller name (e.g., "users")
- `action`: Action name (e.g., "show")
- `method`: HTTP method (GET, POST, etc.)
- `status`: HTTP status code or "exception"
- `status_class`: Status class (2xx, 3xx, 4xx, 5xx)
- `format`: Response format (html, json, etc.)
- `authenticated`: true/false
- `access_level`: User access level if authenticated (user, admin, super_admin, owner)
- `exception`: Exception class name (only for exceptions)

**Helper Methods**:

Controllers can use these methods for custom metrics:

```ruby
# Increment a counter
track_metric("user.signup", tags: { source: "google" })

# Record a measurement
measure_metric("api.response_time", 123.45, tags: { endpoint: "users" })

# Track timing with a block
track_timing("pdf.generation", tags: { type: "invoice" }) do
  generate_pdf
end
```

### 2. Background Jobs (via `ApplicationJob`)

**Location**: `app/jobs/application_job.rb`

Automatically tracks all background jobs via lifecycle callbacks.

**Metrics**:
- `job.enqueued` (counter) - Job was enqueued
- `job.duration` (timing) - Job execution time
- `job.success` (counter) - Job completed successfully
- `job.failure` (counter) - Job failed
- `job.exception` (counter) - Job raised exception

**Tags**:
- `job`: Job class name (e.g., "GoogleCalendarSyncJob")
- `queue`: Queue name (e.g., "default", "critical")
- `attempt`: Execution attempt count
- `exception`: Exception class name (only for failures)

**Helper Methods**:

Jobs can use the same helper methods as controllers:

```ruby
def perform(user)
  track_metric("sync.started", tags: { user_id: user.id })

  track_timing("sync.fetch_data", tags: { user_id: user.id }) do
    fetch_data_from_api
  end
end
```

### 3. Google Calendar Operations

**Location**: `app/services/google_calendar_service.rb`

Tracks calendar operations and sync performance.

**Metrics**:

**Calendar Management**:
- `calendar.created` (counter) - New calendar created
- `calendar.deleted` (counter) - Calendar deleted
- `calendar.create_or_get.duration` (timing) - Time to create or retrieve calendar
- `calendar.delete.duration` (timing) - Time to delete calendar
- `calendar.create.error` (counter) - Calendar creation errors
- `calendar.delete.error` (counter) - Calendar deletion errors

**Sync Operations**:
- `calendar.sync.duration` (timing) - Total sync duration
- `calendar.sync.events.created` (gauge) - Events created in sync
- `calendar.sync.events.updated` (gauge) - Events updated in sync
- `calendar.sync.events.skipped` (gauge) - Events skipped in sync

**Event Operations**:
- `calendar.sync.event.created` (counter) - Individual event created
- `calendar.sync.event.updated` (counter) - Individual event updated
- `calendar.sync.event.deleted` (counter) - Individual event deleted
- `calendar.sync.event.skipped` (counter) - Individual event skipped

**Tags**:
- `user_id`: User ID for the operation
- `newly_created`: true/false (for calendar creation)
- `error`: Error class name (for errors)
- `reason`: Skip reason (e.g., "no_data_change", "user_edit")
- `forced`: true/false (for forced sync)
- `already_deleted`: true/false (for deletions)
- `events`: Number of events processed (for sync duration)

### 4. Database Queries

**Location**: `config/initializers/active_support_notifications.rb`

Automatically tracks all SQL queries via ActiveSupport::Notifications.

**Metrics**:
- `database.query.duration` (timing) - Query execution time
- `database.query.count` (counter) - Number of queries

**Tags**:
- `operation`: SQL operation (select, insert, update, delete, etc.)
- `cached`: true/false - Whether query was cached
- `model`: Model name if available

**Notes**:
- Schema queries (migrations, SHOW, DESCRIBE, EXPLAIN) are excluded
- Helps identify N+1 queries and slow queries

### 5. Cache Operations

**Location**: `config/initializers/active_support_notifications.rb`

Tracks Redis cache operations.

**Metrics**:
- `cache.operation.duration` (timing) - Cache operation time
- `cache.operation.count` (counter) - Number of operations
- `cache.hit` (counter) - Cache hits
- `cache.miss` (counter) - Cache misses

**Tags**:
- `operation`: read, write, delete, exist?, fetch
- `hit`: true/false - Whether operation was a cache hit
- `super_operation`: For fetch operations, the underlying operation (read/write)

### 6. External HTTP API Calls

**Location**: `config/initializers/faraday_statsd.rb`

Tracks HTTP requests made via Faraday to external APIs (RateMyProfessor, LeopardWeb, etc.).

**Metrics**:
- `http.client.request.duration` (timing) - Request duration
- `http.client.request.count` (counter) - Number of requests
- `http.client.request.error` (counter) - 4xx/5xx responses
- `http.client.request.exception` (counter) - Connection exceptions

**Tags**:
- `method`: HTTP method (get, post, etc.)
- `host`: Target hostname
- `status`: HTTP status code or "exception"
- `status_class`: Status class (2xx, 3xx, 4xx, 5xx)
- `exception`: Exception class name (only for exceptions)

**Implementation**:

The `FaradayStatsd` middleware is automatically added to all Faraday clients:

```ruby
connection = Faraday.new(url: "https://api.example.com") do |faraday|
  faraday.use FaradayStatsd
  faraday.request :json
  faraday.adapter Faraday.default_adapter
end
```

### 7. View Rendering

**Location**: `config/initializers/active_support_notifications.rb`

Tracks template and partial rendering.

**Metrics**:
- `view.render.duration` (timing) - Template render time
- `view.render.count` (counter) - Templates rendered
- `view.partial.duration` (timing) - Partial render time
- `view.partial.count` (counter) - Partials rendered

**Tags**:
- `format`: Template format (html, json, etc.)

### 8. Email Delivery

**Location**: `config/initializers/active_support_notifications.rb`

Tracks email sending via Action Mailer.

**Metrics**:
- `mailer.deliver.duration` (timing) - Email delivery time
- `mailer.deliver.count` (counter) - Emails sent

**Tags**:
- `mailer`: Mailer class name

### 9. File Storage

**Location**: `config/initializers/active_support_notifications.rb`

Tracks Active Storage uploads and downloads.

**Metrics**:
- `storage.upload.duration` (timing) - Upload time
- `storage.upload.count` (counter) - Files uploaded
- `storage.download.duration` (timing) - Download time
- `storage.download.count` (counter) - Files downloaded

**Tags**:
- `service`: Storage service name

## Monitoring and Visualization

Metrics can be visualized using tools like:

- **Grafana**: Create dashboards to visualize metrics over time
- **DataDog**: Monitor application performance and set alerts
- **New Relic**: APM integration with StatsD
- **Graphite**: Store and graph time-series data

## Example Grafana Queries

### Request Rate by Controller
```
sumSeries(stats.witccdotdev.server.production.controller.request.count.*)
```

### Average Response Time
```
averageSeries(stats.witccdotdev.server.production.controller.request.duration.*)
```

### Database Query Performance
```
averageSeries(stats.witccdotdev.server.production.database.query.duration.operation:select)
```

### Cache Hit Rate
```
divideSeries(
  sumSeries(stats.witccdotdev.server.production.cache.hit),
  sumSeries(stats.witccdotdev.server.production.cache.*.count)
)
```

### Job Success Rate
```
divideSeries(
  sumSeries(stats.witccdotdev.server.production.job.success),
  sumSeries(stats.witccdotdev.server.production.job.enqueued)
)
```

### Calendar Sync Efficiency
```
averageSeries(stats.witccdotdev.server.production.calendar.sync.events.skipped)
```

## Best Practices

1. **Use Tags Wisely**: Tags create metric cardinality. Avoid high-cardinality tags (user IDs, timestamps, etc.) in production unless necessary.

2. **Measure What Matters**: Focus on metrics that help you understand:
   - User experience (response times, error rates)
   - System health (queue depth, database performance)
   - Business metrics (calendar syncs, user signups)

3. **Set Alerts**: Use your metrics to set up alerts for:
   - High error rates (> 1% 5xx errors)
   - Slow responses (p95 > 1000ms)
   - Job failures (> 5% failure rate)
   - External API errors (> 10% error rate)

4. **Track Custom Metrics**: Use the helper methods in controllers and jobs to track business-specific metrics:

```ruby
# Track feature usage
track_metric("calendar.preference.updated", tags: { preference_type: "color" })

# Track API limits
track_metric("google.api.quota.remaining", quota_remaining)

# Track optimization effectiveness
measure_metric("sync.optimization_rate", skip_percentage)
```

5. **Monitor Resource Usage**: Combine with system metrics (CPU, memory, disk) to correlate application behavior with infrastructure health.

## Debugging Metrics

### Enable StatsD Logging in Development

To see metrics being sent in development:

```ruby
# config/initializers/statsd.rb
if Rails.env.development?
  StatsD.logger = Logger.new(STDOUT)
end
```

### Dry Run Mode

Test metrics without sending to StatsD:

```ruby
ENV["STATSD_ENV"] = "test"
```

### View Metrics in Rails Console

```ruby
# Check if StatsD is enabled
StatsD.backend.class

# Manually send a metric
StatsD.increment("test.metric", tags: ["env:development"])
```

## Performance Impact

The telemetry system is designed to have minimal performance impact:

- **Asynchronous**: Metrics are sent asynchronously (non-blocking)
- **Lightweight**: StatsD uses UDP, so failed sends don't block execution
- **Conditional**: Only enabled in production by default
- **Efficient**: Metrics are aggregated on the StatsD server

Typical overhead: < 1ms per metric, < 5% total application overhead.

## Related Documentation

- [StatsD Protocol](https://github.com/statsd/statsd/blob/master/docs/metric_types.md)
- [statsd-instrument gem](https://github.com/Shopify/statsd-instrument)
- [ActiveSupport::Notifications](https://guides.rubyonrails.org/active_support_instrumentation.html)
