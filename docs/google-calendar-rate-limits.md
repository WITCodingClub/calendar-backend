# Google Calendar rate limits

This page tells how the app handles a rate limit from the Google Calendar API. Issue #679 set these rules.

## Errors

The `google-apis-core` gem picks the error class from the HTTP status and the reason in the body.

| Response | Error class | What the app does |
| --- | --- | --- |
| `429` | `Google::Apis::RateLimitError` | Retries |
| `403` `rateLimitExceeded`, `userRateLimitExceeded`, `sharingRateLimitExceeded` | `Google::Apis::RateLimitError` | Retries |
| `403` with "Quota exceeded ... per minute" in the message | `Google::Apis::ClientError` | Retries |
| `403` `quotaExceeded` ("Calendar usage limits exceeded") | `Google::Apis::ClientError` | Does not retry |
| `403` `dailyLimitExceeded` | `Google::Apis::ClientError` | Does not retry |

`quotaExceeded` and `dailyLimitExceeded` do not reset within minutes, so a retry only waits. See [Google's error guide](https://developers.google.com/workspace/calendar/api/guides/errors).

## Retries

`GoogleCalendar::RateLimiter#with_rate_limit_handling` retries a call in the same thread. A sleep holds a worker thread, so the waits are short:

- In a job: 2 retries, with a wait of at most 8 s (`GOOGLE_API_MAX_RETRIES`, `GOOGLE_API_MAX_DELAY`).
- In a web request: 1 retry, with a wait of at most 2 s.

When the limit lasts longer, the `RateLimitError` leaves the job. A job that calls Google puts itself back in the queue:

```ruby
retry_on Google::Apis::RateLimitError, **GoogleCalendar::RateLimiter::JOB_RETRY
```

The job waits about 3 s, 18 s, 83 s and 258 s, and frees its thread while it waits. After 5 attempts the error goes to the job executor, which reports it. A sync is safe to run again: events that it already made have rows, so the next run updates or skips them.

```mermaid
flowchart TD
  call[Google API call] -->|rate limit| inproc{In-process retries left?}
  inproc -->|yes| sleep[Sleep 1 to 8 s] --> call
  inproc -->|no| job{Job attempts left?}
  job -->|yes| queue[Back in the queue with a wait] --> call
  job -->|no| report[Executor reports the error]
  call -->|quotaExceeded or dailyLimitExceeded| report
```

These jobs retry: `CourseCalendars::SyncJob`, `CourseCalendars::HistoricalSyncJob`, `GoogleCalendar::CreateJob`, `GoogleCalendar::DeleteJob`, `GoogleCalendar::EventDeleteJob`, and the `FriendMeetings::` jobs. Add the `retry_on` line to a new job that calls Google.

When a user has a Google and a Microsoft calendar, `CourseCalendars::ScheduleSyncer` raises an error only when every provider fails. A Google rate limit with a Microsoft success is reported, and the next sync fixes the Google calendar.

## Batch requests

The app does not use batch requests (`CalendarService#batch`). Google counts a batch of n requests as n requests against the usage limits, so a batch does not help with a rate limit. It saves HTTP round trips only.
