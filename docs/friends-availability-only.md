# Friends: share availability without course details

A person can let a friend find a common free time without showing the course list. Each side of a friendship sets a visibility level for its own schedule toward the other side:

- `full`: the friend can read the course list (`processed_events`). This is the default, and the level of each friendship from before this feature.
- `availability_only`: the friend can read only busy blocks (date, start, end). `processed_events` answers 403.

The two sides are independent. If Ada sets `availability_only` toward Grace, Grace sees only Ada's busy blocks, but Ada still sees Grace's courses until Grace changes her own level.

## Feature flag

The flag `friends_availability_only` (`friendsAvailabilityOnly` in `/api/user/feature_flags`) is off by default. The privacy policy must change first (calendar-website#20). Do not turn on the flag for real users before that.

While the flag is off for the signed-in user:

- `GET` and `PATCH /api/friends/:friend_id/visibility` and `GET /api/friends/:friend_id/busy_blocks` answer 404.
- The dashboard does not show the sharing form, and `PATCH /dashboard/friends/:id/visibility` answers 404.

The 403 on `processed_events` does not depend on the flag. A level that a person set while the flag was on stays in force when the flag goes off.

## Flow

```mermaid
sequenceDiagram
    participant E as Extension (viewer)
    participant A as API
    E->>A: POST /api/friends/:id/processed_events
    alt friend shares full
        A-->>E: 200 course list
    else friend shares availability_only
        A-->>E: 403 code AVAILABILITY_ONLY
        E->>A: GET /api/friends/:id/busy_blocks
        A-->>E: 200 busy blocks (date, start, end)
    end
```

## API

All routes need the usual API token.

### GET /api/friends/:friend_id/visibility

Returns both levels, as seen by the signed-in user. `mine` is the level the user set for their own schedule. `theirs` is the level the friend set. `theirs` decides what the user can read.

```json
{ "friend_id": "usr_...", "mine": "full", "theirs": "availability_only" }
```

### PATCH /api/friends/:friend_id/visibility

Body: `{ "visibility": "full" }` or `{ "visibility": "availability_only" }`. Sets the level of the signed-in user's own schedule toward this friend. The answer has the same shape as `GET`.

- 400: `visibility` is missing.
- 403: the user is not an accepted friend.
- 422: `visibility` is not `full` or `availability_only`.

### GET /api/friends/:friend_id/busy_blocks

Query: `start_date` and `end_date`, in `YYYY-MM-DD` format. Both are optional. `start_date` defaults to today, and `end_date` to six days after `start_date`. The range is 120 days or fewer.

Every accepted friend can read busy blocks, whatever the friend's level.

```json
{
  "time_zone": "America/New_York",
  "start_date": "2026-10-05",
  "end_date": "2026-10-11",
  "busy": [
    { "date": "2026-10-05", "weekday": "monday", "start": "09:00", "end": "10:15" }
  ]
}
```

- Times are wall-clock times in `time_zone`.
- Blocks on one date that overlap or touch are merged into one block.
- The list does not remove holidays. A block on a holiday says "busy" when the friend is free.
- 400: a date has the wrong format, `end_date` is before `start_date`, or the range is too long.
- 403: the user is not an accepted friend.

### POST /api/friends/:friend_id/processed_events

Unchanged for a friend who shares `full`. For a friend who shares `availability_only`:

```json
{ "error": "This friend shares only availability", "code": "AVAILABILITY_ONLY", "visibility": "availability_only" }
```

with status 403.

## Code

- `BusyBlocks` (`app/services/busy_blocks.rb`) computes the blocks for one user and a date range in one query. It loads no course record. Other features, such as a one-time meeting link (#652), can use it.
- `BusyBlocksSerializer` and `FriendshipVisibilitySerializer` render the API answers.
- `Friendship#visibility_set_by`, `#update_visibility_for!` and `#full_schedule_visible_to?` hold the rules.
- The dashboard friend page shows the busy blocks for one week in place of the course list when the friend shares only availability.
