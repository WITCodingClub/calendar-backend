# Calendar Preferences API Guide

## Overview

The Calendar Preferences system allows users to customize how their calendar events appear in Google Calendar. All configuration is done through the Chrome extension, which communicates with these API endpoints.

## Architecture

### Three-Tier Preference Hierarchy

Preferences are resolved in this order (first match wins):

1. **Individual Event** - Specific override for a single meeting (e.g., "Wednesday's COMP-101 lecture")
2. **Event Type** - Defaults for all events of a type (e.g., all "laboratory" classes)
3. **Global** - User's default for all events
4. **System Defaults** - Built-in fallbacks:
   - Title: `{{class_name}}`
   - Description: `{{faculty}}\n{{faculty_email}}`
   - Location: `{{building}} {{room}}`
   - Reminders: 30 minutes before (popup)
   - Visibility: default

### What Can Be Customized

Each preference level can configure:
- **Title Template** - Liquid template for event summary (e.g., `{{course_code}}: {{title}}`)
- **Description Template** - Liquid template for event description
- **Location Template** - Liquid template for event location (e.g., `{{building}} - {{room}}`)
- **Reminder Settings** - Array of reminders with minutes and method (popup/email)
- **Color** - Google Calendar color ID (1-11)
- **Visibility** - Event visibility (public, private, default)

## Authentication

All API endpoints require JWT authentication. Include the token in the Authorization header:

```http
Authorization: Bearer <jwt_token>
```

## API Endpoints

### Quick Reference

The API provides access to preferences at three levels:

1. **Global & Event Type Preferences** (endpoints 1-5)
   - `/api/calendar_preferences` - Manage user-wide defaults
   - Use `:id` parameter as `"global"` or event type name (e.g., `"lecture"`)

2. **Individual Event Preferences** (endpoints 6-8)
   - `/api/meeting_times/:meeting_time_id/preference` - Configure specific meeting times
   - `/api/google_calendar_events/:google_calendar_event_id/preference` - Configure specific calendar events
   - Use the **event's ID** to get/update/delete that specific event's configuration

3. **Template Preview** (endpoint 5)
   - `/api/calendar_preferences/preview` - Test templates before saving

**Example: Getting Config for a Specific Event**

To get the current configuration for meeting time #123:
```http
GET /api/meeting_times/123/preference
Authorization: Bearer <token>
```

This returns the individual overrides (if any) AND the resolved preferences after walking the hierarchy.

---

### 1. List All User Preferences

Get all calendar preferences for the authenticated user.

**Endpoint:** `GET /api/calendar_preferences`

**Response:**
```json
{
  "global": {
    "scope": "global",
    "event_type": null,
    "title_template": "{{course_code}}: {{title}}",
    "description_template": null,
    "location_template": null,
    "reminder_settings": [
      {"minutes": 15, "method": "popup"}
    ],
    "color_id": null,
    "visibility": null
  },
  "event_types": {
    "lecture": {
      "scope": "event_type",
      "event_type": "lecture",
      "title_template": "{{course_code}}: {{title}}",
      "description_template": null,
      "location_template": null,
      "reminder_settings": null,
      "color_id": 1,
      "visibility": null
    },
    "laboratory": {
      "scope": "event_type",
      "event_type": "laboratory",
      "title_template": "{{title}} - Lab ({{room}})",
      "description_template": null,
      "location_template": "{{building}} - Room {{room}}",
      "reminder_settings": [
        {"minutes": 30, "method": "popup"},
        {"minutes": 1440, "method": "email"}
      ],
      "color_id": 7,
      "visibility": null
    }
  }
}
```

**Use Case:** Initial load of extension preferences UI

---

### 2. Get Specific Preference

Get a single preference (global or event type).

**Endpoint:** `GET /api/calendar_preferences/:id`

**Parameters:**
- `:id` - Either `"global"` or an event type name (e.g., `"lecture"`, `"laboratory"`, `"hybrid"`)

**Example:** `GET /api/calendar_preferences/lecture`

**Response:**
```json
{
  "scope": "event_type",
  "event_type": "lecture",
  "title_template": "{{course_code}}: {{title}}",
  "description_template": null,
  "location_template": null,
  "reminder_settings": null,
  "color_id": 1,
  "visibility": null
}
```

---

### 3. Update Global or Event Type Preference

Create or update a preference at global or event-type level.

**Endpoint:** `PUT /api/calendar_preferences/:id`

**Parameters:**
- `:id` - Either `"global"` or an event type name

**Request Body:**
```json
{
  "calendar_preference": {
    "title_template": "{{day_abbr}} {{start_time}}: {{title}}",
    "description_template": "{{course_code}}\nInstructor: {{faculty}}",
    "location_template": "{{building}} - {{room}}",
    "reminder_settings": [
      {"minutes": 30, "method": "popup"}
    ],
    "color_id": 5,
    "visibility": "default"
  }
}
```

**Field Specifications:**
- `title_template` (string, max 500 chars) - Liquid template for event title
- `description_template` (string, max 2000 chars) - Liquid template for description
- `location_template` (string, max 500 chars) - Liquid template for event location
- `reminder_settings` (array) - Array of `{minutes: integer, method: "popup"|"notification"|"email"}` objects
  - **Note:** `"notification"` is an alias for `"popup"` and will be normalized to `"popup"`
- `color_id` (integer, 1-11) - Google Calendar color ID
- `visibility` (string) - One of: `"public"`, `"private"`, `"default"`

**Example:** Set global preferences
```http
PUT /api/calendar_preferences/global
Content-Type: application/json
Authorization: Bearer <token>

{
  "calendar_preference": {
    "title_template": "{{course_code}}: {{title}}",
    "reminder_settings": [
      {"minutes": 15, "method": "popup"}
    ]
  }
}
```

**Response:** Same as Get Specific Preference

**Validation Errors:**
```json
{
  "errors": [
    "Title template invalid syntax: unexpected token",
    "Color id must be between 1 and 11"
  ]
}
```

---

### 4. Delete Preference

Remove a preference (reverts to next level in hierarchy).

**Endpoint:** `DELETE /api/calendar_preferences/:id`

**Parameters:**
- `:id` - Event type name (cannot delete global, only update it to empty/null values)

**Example:** `DELETE /api/calendar_preferences/laboratory`

**Response:** `204 No Content`

---

### 5. Preview Template

Test a template with real data before saving.

**Endpoint:** `POST /api/calendar_preferences/preview`

**Request Body:**
```json
{
  "template": "{{day_abbr}} {{start_time}}: {{title}} in {{room}}",
  "meeting_time_id": 42
}
```

**Parameters:**
- `template` (string, required) - Liquid template to test
- `meeting_time_id` (integer, required) - ID of a meeting time to render against

**Success Response:**
```json
{
  "rendered": "Mon 9:00 AM: Computer Science I in 306",
  "valid": true
}
```

**Validation Error Response:**
```json
{
  "valid": false,
  "error": "Disallowed variables: invalid_var"
}
```

**Use Case:** Live preview in extension as user types template

---

### 6. Get Preference for a Specific Event by ID

Get preferences for a **specific event** using its meeting time ID or calendar event ID. This returns both the individual overrides (if any) AND the resolved preferences after walking the hierarchy.

**Endpoints:**
- `GET /api/meeting_times/:meeting_time_id/preference` - Get config for a specific meeting time
- `GET /api/google_calendar_events/:google_calendar_event_id/preference` - Get config for a specific calendar event

**Parameters:**
- `:meeting_time_id` - The ID of the specific meeting time you want to configure
- `:google_calendar_event_id` - Alternative: use the GoogleCalendarEvent ID

**Response:**
```json
{
  "individual_preference": {
    "title_template": null,
    "description_template": null,
    "location_template": null,
    "reminder_settings": [
      {"minutes": 60, "method": "popup"}
    ],
    "color_id": null,
    "visibility": null
  },
  "resolved": {
    "title_template": "{{title}} - Lab ({{room}})",
    "description_template": "Instructor: {{faculty}}",
    "location_template": "{{building}} - Room {{room}}",
    "reminder_settings": [
      {"minutes": 60, "method": "popup"}
    ],
    "color_id": 7,
    "visibility": "default"
  },
  "sources": {
    "title_template": "event_type:laboratory",
    "description_template": "event_type:laboratory",
    "location_template": "event_type:laboratory",
    "reminder_settings": "individual",
    "color_id": "event_type:laboratory",
    "visibility": "global"
  },
  "preview": {
    "title": "Computer Science I - Lab (306)",
    "description": "Instructor: Dr. Jane Smith",
    "location": "Wentworth Hall - Room 306"
  }
}
```

**Response Fields:**
- `individual_preference` - Only the overrides set specifically for this event (null if not set)
- `resolved` - Actual values that will be used (after walking the hierarchy)
- `sources` - Where each value came from (useful for UI to show inheritance)
- `preview` - Rendered event preview with actual values using resolved templates:
  - `title` (string) - Rendered event title
  - `description` (string) - Rendered event description
  - `location` (string) - Rendered event location

**Use Case:**
- Display current settings when user clicks on a specific event
- Show where each setting is inherited from

---

### 7. Update Preference for a Specific Event by ID

Set an override for a **specific event** using its meeting time ID or calendar event ID.

**Endpoints:**
- `PUT /api/meeting_times/:meeting_time_id/preference` - Update config for a specific meeting time
- `PUT /api/google_calendar_events/:google_calendar_event_id/preference` - Update config for a specific calendar event

**Parameters:**
- `:meeting_time_id` - The ID of the specific meeting time you want to configure
- `:google_calendar_event_id` - Alternative: use the GoogleCalendarEvent ID

**Request Body:**
```json
{
  "event_preference": {
    "location_template": "Room {{room}} ({{building}})",
    "reminder_settings": [
      {"minutes": 60, "method": "popup"}
    ]
  }
}
```

**Notes:**
- Only include fields you want to override
- Setting a field to `null` removes that specific override (falls back to hierarchy)
- At least one non-null field is required
- Allowed fields: `title_template`, `description_template`, `location_template`, `reminder_settings`, `color_id`, `visibility`

**Response:** Same as section 6 (Get Preference for a Specific Event by ID)

---

### 8. Delete Preference for a Specific Event by ID

Remove all overrides for a **specific event** using its meeting time ID or calendar event ID. After deletion, the event will fall back to event-type/global/system defaults.

**Endpoints:**
- `DELETE /api/meeting_times/:meeting_time_id/preference` - Delete config for a specific meeting time
- `DELETE /api/google_calendar_events/:google_calendar_event_id/preference` - Delete config for a specific calendar event

**Parameters:**
- `:meeting_time_id` - The ID of the specific meeting time
- `:google_calendar_event_id` - Alternative: use the GoogleCalendarEvent ID

**Response:** `204 No Content`

---

## Template Variables

Templates use Liquid syntax. Available variables:

### Course Information
- `{{title}}` - Course title (e.g., "Computer Science I")
- `{{course_code}}` - Full code (e.g., "COMP-101-01")
- `{{subject}}` - Subject code (e.g., "COMP")
- `{{course_number}}` - Course number (e.g., "101")
- `{{section_number}}` - Section (e.g., "01")
- `{{crn}}` - Course Reference Number (e.g., "12345")

### Location Information
- `{{room}}` - Room number/name (e.g., "306")
- `{{building}}` - Building name (e.g., "Wentworth Hall")
- `{{location}}` - Pre-formatted location (e.g., "Wentworth Hall - 306")

### Faculty Information
- `{{faculty}}` - Primary instructor (e.g., "Dr. Jane Smith")
- `{{all_faculty}}` - All instructors (e.g., "Dr. Smith, Prof. Jones")

### Time Information
- `{{start_time}}` - Start time (e.g., "9:00 AM")
- `{{end_time}}` - End time (e.g., "10:30 AM")
- `{{day}}` - Full day name (e.g., "Monday")
- `{{day_abbr}}` - Abbreviated day (e.g., "Mon")

### Academic Information
- `{{term}}` - Academic term (e.g., "Spring 2024")
- `{{schedule_type}}` - Type (e.g., "lecture", "laboratory", "hybrid")

### Liquid Features
```liquid
{{course_code}}: {{title}}
→ "COMP-101-01: Computer Science I"

{{day_abbr}} {{start_time}}: {{title}}
→ "Mon 9:00 AM: Computer Science I"

{% if faculty %}Instructor: {{faculty}}{% endif %}
→ "Instructor: Dr. Smith" (if faculty exists)

{% case schedule_type %}
  {% when 'laboratory' %}Lab: {{title}}
  {% when 'lecture' %}Class: {{title}}
  {% else %}{{title}}
{% endcase %}
→ "Lab: Computer Science I" (if laboratory)
```

See `/docs/template_variables.md` for complete reference.

---

## Color IDs

Google Calendar supports 11 colors:

| ID | Name |
|----|------|
| 1  | Lavender |
| 2  | Sage |
| 3  | Grape |
| 4  | Flamingo |
| 5  | Banana |
| 6  | Tangerine |
| 7  | Peacock |
| 8  | Graphite |
| 9  | Blueberry |
| 10 | Basil |
| 11 | Tomato |

---

## Common Workflows

### Initial Setup (Extension)

1. User opens extension preferences
2. Extension calls `GET /api/calendar_preferences`
3. Display current global and event-type preferences
4. User can edit and save via `PUT /api/calendar_preferences/:id`

### Per-Event Configuration

1. User clicks on a specific class in the extension
2. Extension calls `GET /api/meeting_times/:id/preference`
3. Display resolved preferences with inheritance sources
4. User can override specific properties
5. Extension calls `PUT /api/meeting_times/:id/preference` with only changed fields

### Template Editing with Live Preview

1. User types template in extension UI
2. Extension debounces and calls `POST /api/calendar_preferences/preview`
   - Include a sample `meeting_time_id` from user's schedule
3. Display rendered result in real-time
4. On save, call `PUT /api/calendar_preferences/:id`

### Bulk Event Configuration

1. Extension shows list of all user's meeting times
2. For each, display current preferences via `GET /api/meeting_times/:id/preference`
3. User can click to override any individual event
4. Extension calls `PUT /api/meeting_times/:id/preference` for each override

---

## Event Type Names

The following event types are currently supported:

- `lecture` - Regular lecture classes
- `laboratory` - Lab sessions
- `hybrid` - Hybrid classes (online + in-person)

Additional types may be added as the system evolves.

---

## Example Extension Flows

### Flow 1: Set Global Default

**User Action:** "I want all my events to show the day and time in the title"

**Extension Steps:**
```javascript
// 1. User enters template
const template = "{{day_abbr}} {{start_time}}: {{title}}"

// 2. Preview with first meeting time
const preview = await fetch('/api/calendar_preferences/preview', {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${token}`,
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({
    template: template,
    meeting_time_id: userMeetingTimes[0].id
  })
})

// 3. Show preview: "Mon 9:00 AM: Computer Science I"
displayPreview(preview.rendered)

// 4. User clicks save
await fetch('/api/calendar_preferences/global', {
  method: 'PUT',
  headers: {
    'Authorization': `Bearer ${token}`,
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({
    calendar_preference: {
      title_template: template
    }
  })
})

// 5. Trigger calendar re-sync
triggerCalendarSync()
```

---

### Flow 2: Different Reminders for Wednesday Class

**User Action:** "I want a 1-hour reminder for my Wednesday COMP-101 class instead of the default 15 minutes"

**Extension Steps:**
```javascript
// 1. Get Wednesday meeting time ID
const wednesdayMeeting = userMeetings.find(m =>
  m.course_code === 'COMP-101-01' && m.day_of_week === 'wednesday'
)

// 2. Get current settings to show user what will change
const current = await fetch(
  `/api/meeting_times/${wednesdayMeeting.id}/preference`,
  {
    headers: { 'Authorization': `Bearer ${token}` }
  }
)

// 3. Show user: "Currently using global default: 15 min popup"
// 4. User sets override: 60 min popup

// 5. Save override
await fetch(`/api/meeting_times/${wednesdayMeeting.id}/preference`, {
  method: 'PUT',
  headers: {
    'Authorization': `Bearer ${token}`,
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({
    event_preference: {
      reminder_settings: [
        { minutes: 60, method: 'popup' }
      ]
    }
  })
})

// 6. Trigger calendar re-sync
triggerCalendarSync()
```

---

### Flow 3: Lab-Specific Templates

**User Action:** "I want all my labs to show the room number in the title"

**Extension Steps:**
```javascript
// 1. User selects "laboratory" event type
// 2. User enters template
const template = "{{title}} - Lab in {{room}}"

// 3. Preview with a laboratory meeting
const labMeeting = userMeetings.find(m => m.schedule_type === 'laboratory')
const preview = await fetch('/api/calendar_preferences/preview', {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${token}`,
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({
    template: template,
    meeting_time_id: labMeeting.id
  })
})

// 4. Show preview: "Computer Science I - Lab in 306"

// 5. User clicks save
await fetch('/api/calendar_preferences/laboratory', {
  method: 'PUT',
  headers: {
    'Authorization': `Bearer ${token}`,
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({
    calendar_preference: {
      title_template: template,
      color_id: 7  // Peacock blue for labs
    }
  })
})

// 6. Trigger calendar re-sync
triggerCalendarSync()
```

---

## Error Handling

### Validation Errors (422 Unprocessable Entity)

```json
{
  "errors": [
    "Title template invalid syntax: unexpected token at line 1",
    "Reminder settings item 0 must have integer 'minutes' field",
    "Color id must be between 1 and 11"
  ]
}
```

**Extension Should:**
- Display errors inline near the relevant field
- Prevent saving until errors are resolved
- Use preview endpoint to validate templates before saving

### Not Found Errors (404)

Occurs when meeting_time_id or google_calendar_event_id doesn't exist.

**Extension Should:**
- Verify IDs before making requests
- Handle gracefully with user-friendly message

### Authentication Errors (401)

Token expired or invalid.

**Extension Should:**
- Refresh JWT token
- Redirect to login if refresh fails

---

## Best Practices for Extension

### 1. Caching
- Cache `GET /api/calendar_preferences` response
- Only refetch when user explicitly opens preferences
- Cache meeting time IDs to avoid repeated lookups

### 2. Debouncing
- Debounce preview requests (300-500ms) as user types
- Batch updates when possible

### 3. User Feedback
- Show loading states during API calls
- Display success/error messages clearly
- Show inheritance sources (e.g., "Using global default")

### 4. Template Validation
- Use preview endpoint for real-time validation
- Show syntax errors immediately
- Provide autocomplete for variables

### 5. Sync Triggering
- After preference changes, trigger calendar re-sync
- Show progress/status to user
- Handle sync failures gracefully

---

## Security Notes

- All endpoints require JWT authentication
- Users can only access/modify their own preferences
- Templates are sandboxed (Liquid prevents code execution)
- Only whitelisted variables are allowed
- Input validation on all fields

---

## Performance Considerations

- Preference resolution is cached per request
- Template rendering is fast (Liquid is efficient)
- No N+1 queries (uses includes/joins)
- Preview endpoint is lightweight (single meeting time)

---

## Future Enhancements

Potential additions being considered:

- **Template Library** - Preset templates users can choose from
- **Bulk Operations** - Apply preferences to multiple events at once
- **Import/Export** - Share preference configs between users
- **Smart Suggestions** - ML-based template recommendations
- **Additional Variables** - GPA, credits, assignment due dates
- **Conditional Reminders** - Different reminders based on time/day
- **More Notification Channels** - SMS, push notifications
