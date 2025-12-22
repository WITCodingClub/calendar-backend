# Course Reprocess API

## Overview

The `/api/courses/reprocess` endpoint allows users to refresh their course schedule when they've made changes in LeopardWeb (e.g., switching sections, adding/dropping courses). It compares the new course list with existing enrollments and intelligently merges them.

## Endpoint

```
POST /api/courses/reprocess
```

## Authentication

Requires JWT token in Authorization header:
```
Authorization: Bearer <jwt_token>
```

## Request Body

Same format as `/api/process_courses`:

```json
{
  "courses": [
    {
      "crn": "12345",
      "term": "202501",
      "courseNumber": "101",
      "start": "2025-01-13",
      "end": "2025-05-09"
    },
    {
      "crn": "67890",
      "term": "202501",
      "courseNumber": "102",
      "start": "2025-01-13",
      "end": "2025-05-09"
    }
  ]
}
```

### Parameters

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `courses` | array | Yes | Array of course objects |
| `courses[].crn` | string/int | Yes | Course Reference Number from LeopardWeb |
| `courses[].term` | string | Yes | Term UID (e.g., "202501" for Spring 2025) |
| `courses[].courseNumber` | string/int | No | Course number (e.g., "101") |
| `courses[].start` | string | No | Course start date (ISO 8601 format) |
| `courses[].end` | string | No | Course end date (ISO 8601 format) |

**Note:** All courses in the request must be from the same term.

## Response

### Success (200 OK)

```json
{
  "ics_url": "https://backend.example.com/calendar/abc123.ics",
  "removed_enrollments": 1,
  "removed_courses": [
    {
      "crn": 11111,
      "title": "English Composition I",
      "course_number": 101
    }
  ],
  "processed_courses": [
    {
      "id": 42,
      "title": "English Composition I",
      "course_number": 101,
      "schedule_type": "LEC",
      "term": {
        "uid": "202501",
        "season": "spring",
        "year": 2025
      },
      "meeting_times": [
        {
          "begin_time": "09:00 AM",
          "end_time": "09:50 AM",
          "start_date": "2025-01-13",
          "end_date": "2025-05-09",
          "day_of_week": "monday",
          "location": {
            "building": {
              "name": "Main Building",
              "abbreviation": "MB"
            },
            "room": "101"
          }
        }
      ]
    }
  ]
}
```

### Response Fields

| Field | Type | Description |
|-------|------|-------------|
| `ics_url` | string | URL to the user's calendar feed |
| `removed_enrollments` | int | Number of enrollments removed (courses no longer in schedule) |
| `removed_courses` | array | Details of courses that were removed |
| `processed_courses` | array | Details of all courses in the new schedule |

### Error Responses

**400 Bad Request** - No courses provided or invalid input:
```json
{
  "error": "No courses provided"
}
```

```json
{
  "error": "All courses must be from the same term"
}
```

**500 Internal Server Error** - Processing failed:
```json
{
  "error": "Failed to reprocess courses"
}
```

## How It Works

1. **Compare CRNs**: Compares the CRNs in the request with user's existing enrollments for the term
2. **Remove old enrollments**: Enrollments with CRNs not in the new list are removed
3. **Clean up calendar**: Google Calendar events for removed courses are deleted
4. **Process new courses**: Fetches fresh data from LeopardWeb and creates/updates enrollments
5. **Sync calendar**: Triggers Google Calendar sync to add new events

### Example Scenario

User has:
- ENG-101 Section A (CRN: 11111)
- MATH-102 (CRN: 22222)

User switches to ENG-101 Section B in LeopardWeb (CRN: 33333).

Frontend sends reprocess request with:
- ENG-101 Section B (CRN: 33333)
- MATH-102 (CRN: 22222)

Result:
- ENG-101 Section A (CRN: 11111) is removed
- MATH-102 (CRN: 22222) stays unchanged
- ENG-101 Section B (CRN: 33333) is added

## Difference from `/api/process_courses`

| Aspect | `/api/process_courses` | `/api/courses/reprocess` |
|--------|------------------------|--------------------------|
| Purpose | Initial course processing | Refresh after schedule changes |
| Old enrollments | Keeps all existing | Removes ones not in new list |
| Calendar cleanup | No | Yes, removes events for dropped courses |
| Use case | First time setup | After changing schedule in LeopardWeb |

## Frontend Implementation Notes

1. **When to call this endpoint**: When user clicks a "Refresh Schedule" button or similar
2. **Get current courses**: Fetch current course list from LeopardWeb the same way as initial sync
3. **Send all courses**: Send ALL courses for the term, not just changed ones
4. **Handle response**: Show user what was removed and what was added
5. **Same format**: Request format is identical to `/api/process_courses`

## Logging

The service logs detailed information for debugging:

```
[CourseReprocess] Starting reprocess for user 123 (user@example.com), term 202501 (Spring 2025)
[CourseReprocess] User 123: Current CRNs: [11111, 22222]
[CourseReprocess] User 123: New CRNs: [33333, 22222]
[CourseReprocess] User 123: CRNs to remove: [11111]
[CourseReprocess] User 123: CRNs to add: [33333]
[CourseReprocess] User 123: CRNs unchanged: [22222]
[CourseReprocess] User 123: Removing enrollment for course CRN 11111 (English Composition I)
[CourseReprocess] User 123: Deleted 3 calendar events for CRN 11111
[CourseReprocess] User 123: Completed - removed 1 enrollments, processed 2 courses
```

## Related

- [Intelligent Calendar Sync](../calendar-sync/intelligent_calendar_sync.md) - How calendar events are synced
- [Course Processor Service](../../app/services/course_processor_service.rb) - Initial course processing logic
