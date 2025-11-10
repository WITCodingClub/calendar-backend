# Google API Rate Limiting

This document describes the rate limiting implementation for Google Calendar API calls in the application.

## Overview

The application implements comprehensive rate limiting and retry logic to handle Google Calendar API quotas gracefully. This prevents API quota exhaustion and ensures reliable operation even under high load.

## Google Calendar API Quotas

Google Calendar API has the following default quotas:

- **Queries per day**: 1,000,000
- **Queries per 100 seconds per user**: 1,500
- **Queries per 100 seconds (total)**: 20,000

The most commonly hit limit is the per-user quota of 1,500 queries per 100 seconds.

## Implementation

### GoogleApiRateLimiter Concern

Location: `app/services/concerns/google_api_rate_limiter.rb`

The `GoogleApiRateLimiter` concern provides:

1. **Exponential backoff** for rate limit errors (429 status)
2. **Configurable retry logic** with jitter to prevent thundering herd
3. **Batch throttling** for operations that process multiple items
4. **Retry-After header support** for respecting Google's suggested delays

### Key Features

#### 1. Automatic Retry with Exponential Backoff

When a rate limit error is encountered, the system automatically retries with exponentially increasing delays:

```ruby
# First retry: ~1 second
# Second retry: ~2 seconds
# Third retry: ~4 seconds
# Fourth retry: ~8 seconds
# Fifth retry: ~16 seconds
```

Jitter (±25% randomness) is added to prevent multiple servers from retrying simultaneously.

#### 2. Rate Limit Error Detection

The system detects rate limit errors in multiple ways:

- `Google::Apis::RateLimitError` exceptions
- `Google::Apis::ClientError` with status code 429
- Error messages containing "rate limit" or "quota exceeded"

#### 3. Batch Throttling

For operations that process multiple items (e.g., deleting multiple events, sharing calendar with multiple emails), the system adds a configurable delay between operations:

```ruby
with_batch_throttling(items) do |item|
  # Process item
end
```

This prevents hitting rate limits when processing large batches.

## Configuration

Configuration is located in `config/initializers/google_api_rate_limiting.rb`.

### Environment Variables

You can override the default configuration using environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `GOOGLE_API_MAX_RETRIES` | 5 | Maximum number of retry attempts |
| `GOOGLE_API_INITIAL_DELAY` | 1.0 | Initial delay in seconds before first retry |
| `GOOGLE_API_MAX_DELAY` | 32.0 | Maximum delay in seconds (caps exponential backoff) |
| `GOOGLE_API_BACKOFF_MULTIPLIER` | 2.0 | Multiplier for exponential backoff |
| `GOOGLE_API_BATCH_THROTTLE_DELAY` | 0.1 | Delay in seconds between batch operations |

### Adjusting Configuration

To increase the delay between batch operations (safer but slower):

```bash
export GOOGLE_API_BATCH_THROTTLE_DELAY=0.5
```

To reduce retry attempts (fail faster):

```bash
export GOOGLE_API_MAX_RETRIES=3
```

## Usage in GoogleCalendarService

The `GoogleCalendarService` includes the `GoogleApiRateLimiter` concern and wraps all Google Calendar API calls with rate limit handling.

### Single API Call

```ruby
with_rate_limit_handling do
  service.insert_event(calendar_id, event)
end
```

### Batch Operations

```ruby
with_batch_throttling(events) do |event|
  # Rate limit handling is automatically applied
  delete_event_from_calendar(service, calendar, event)
end
```

## Protected Operations

The following Google Calendar operations are protected with rate limiting:

### Calendar Operations
- `create_calendar_with_service_account` - Create calendar
- `delete_calendar` - Delete calendar
- `list_calendars` - List user's calendars
- `get_available_colors` - Get color options

### ACL (Sharing) Operations
- `share_calendar_with_user` - Share with all user emails (batch throttled)
- `share_calendar_with_email` - Share with single email
- `unshare_calendar_with_email` - Remove sharing

### Calendar List Operations
- `add_calendar_to_all_oauth_users` - Add to multiple users (batch throttled)
- `add_calendar_to_user_list_for_email` - Add to single user
- `remove_calendar_from_user_list_for_email` - Remove from user list

### Event Operations
- `create_event_in_calendar` - Create single event
- `update_event_in_calendar` - Update event (includes get + update)
- `delete_event_from_calendar` - Delete single event
- `clear_calendar_events` - Delete all events (batch throttled)

## Monitoring

### Logging

Rate limit events are logged at different levels:

**Warnings** (retry attempts):
```
Google API rate limit hit (attempt 1/5). Retrying in 1.2 seconds.
```

**Errors** (max retries exceeded):
```
Google API rate limit exceeded after 5 retries. Giving up.
```

### Best Practices

1. **Monitor logs** for rate limit warnings - frequent warnings indicate you may need to:
   - Increase `GOOGLE_API_BATCH_THROTTLE_DELAY`
   - Reduce the frequency of sync operations
   - Spread out operations over time

2. **Use background jobs** for operations that can tolerate delays:
   - `NightlyCalendarSyncJob` spreads syncs throughout the night
   - `GoogleCalendarSyncJob` for user-initiated syncs

3. **Leverage the hash-based change detection** to avoid unnecessary API calls:
   - Only events with actual changes trigger API calls
   - User edits in Google Calendar are preserved

## Troubleshooting

### Problem: Frequent Rate Limit Warnings

**Symptoms**: Logs show many "Google API rate limit hit" warnings

**Solutions**:
1. Increase batch throttle delay: `GOOGLE_API_BATCH_THROTTLE_DELAY=0.2`
2. Check if multiple servers are syncing the same user simultaneously
3. Review background job scheduling to spread out API calls

### Problem: Sync Jobs Failing

**Symptoms**: Jobs fail with "Rate limit exceeded after N retries"

**Solutions**:
1. Increase max retries: `GOOGLE_API_MAX_RETRIES=10`
2. Increase max delay: `GOOGLE_API_MAX_DELAY=64.0`
3. Add delays between processing different users in batch jobs

### Problem: Slow Sync Performance

**Symptoms**: Calendar syncs take a long time

**Solutions**:
1. Reduce batch throttle delay (if not hitting rate limits): `GOOGLE_API_BATCH_THROTTLE_DELAY=0.05`
2. Ensure background jobs are running (not blocking the main thread)
3. Review the number of events being synced

## Technical Details

### Retry Logic Flow

```
1. Make API call
2. If rate limit error:
   a. Check if max retries exceeded → raise error
   b. Calculate delay with exponential backoff + jitter
   c. Check for Retry-After header → use if present
   d. Sleep for calculated delay
   e. Log warning
   f. Retry from step 1
3. If other error → raise immediately
4. If success → return result
```

### Jitter Calculation

Jitter prevents thundering herd by adding randomness:

```ruby
base_delay = 1.0 * (2.0 ** (attempt - 1))  # Exponential backoff
jitter_factor = 0.75 + (rand * 0.5)         # Between 0.75 and 1.25
actual_delay = base_delay * jitter_factor
```

For attempt 3 with default settings:
- Base delay: 4.0 seconds
- Actual delay: 3.0 - 5.0 seconds (varies per request)

## Testing

Comprehensive tests are located in `spec/services/concerns/google_api_rate_limiter_spec.rb`.

Run tests:
```bash
bundle exec rspec spec/services/concerns/google_api_rate_limiter_spec.rb
```

## See Also

- [Google Calendar API Quotas](https://developers.google.com/calendar/api/guides/quota)
- [Job Queues Documentation](docs/infrastructure/job-queues.md)
- [Intelligent Calendar Sync](docs/calendar-sync/intelligent_calendar_sync.md)
