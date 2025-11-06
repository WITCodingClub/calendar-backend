# Calendar Preferences System

## Overview

The Calendar Preferences System allows users to customize how their calendar events are displayed, including titles, descriptions, reminders, colors, and visibility settings. It supports a hierarchical configuration model where preferences can be set at multiple levels with specific overrides.

**📱 For Chrome Extension Developers:** See the [Extension Integration Guide](./extension_integration_guide.md) and [API Documentation](./api_calendar_preferences.md) for implementation details.

**Note:** All calendar preference configuration is done through the Chrome extension UI, which communicates with the backend API endpoints.

## Architecture

### Three-Tier Preference Hierarchy

Preferences are resolved using a fallback chain:

1. **Individual Event Level** - Specific overrides for a single meeting time or calendar event
2. **Event Type Level** - Defaults for all events of a type (lecture, laboratory, hybrid, etc.)
3. **Global Level** - User's default preferences for all events
4. **System Defaults** - Built-in fallback templates (hardcoded)

When rendering an event, the system walks up this chain until it finds a defined value for each property.

### Database Models

#### CalendarPreference

Stores global and event-type level preferences for a user.

**Columns:**
- `user_id` (references users) - Owner of the preference
- `scope` (enum: `global`, `event_type`) - Scope of this preference
- `event_type` (string, nullable) - Type of event (lecture, laboratory, hybrid, etc.) - only set when scope=event_type
- `title_template` (text) - Liquid template for event title
- `description_template` (text) - Liquid template for event description
- `reminder_settings` (jsonb) - Array of reminder configurations
- `color_id` (integer) - Google Calendar color ID (1-11)
- `visibility` (string) - Event visibility (public, private, default)

**Constraints:**
- Unique on `[user_id, scope, event_type]`
- `event_type` required when `scope = 'event_type'`
- `event_type` must be null when `scope = 'global'`

**Example Records:**
```ruby
# Global default for user
{
  user_id: 1,
  scope: 'global',
  event_type: nil,
  title_template: '{{course_code}}: {{title}}',
  reminder_settings: [{minutes: 15, method: 'popup'}]
}

# Event type default for laboratories
{
  user_id: 1,
  scope: 'event_type',
  event_type: 'laboratory',
  title_template: '{{title}} - Lab ({{room}})',
  color_id: 7,
  reminder_settings: [{minutes: 30, method: 'popup'}, {minutes: 1440, method: 'email'}]
}
```

#### EventPreference

Stores individual event-level preference overrides. Uses polymorphic association to support both MeetingTime and GoogleCalendarEvent.

**Columns:**
- `user_id` (references users) - Owner (denormalized for query performance)
- `preferenceable_type` (string) - Polymorphic type (MeetingTime or GoogleCalendarEvent)
- `preferenceable_id` (bigint) - Polymorphic ID
- `title_template` (text, nullable) - Override title template
- `description_template` (text, nullable) - Override description template
- `reminder_settings` (jsonb, nullable) - Override reminder settings
- `color_id` (integer, nullable) - Override color
- `visibility` (string, nullable) - Override visibility

**Constraints:**
- Unique on `[user_id, preferenceable_type, preferenceable_id]`
- Index on `[preferenceable_type, preferenceable_id]`

**Example Record:**
```ruby
# Override for specific Wednesday meeting
{
  user_id: 1,
  preferenceable_type: 'MeetingTime',
  preferenceable_id: 42,
  reminder_settings: [{minutes: 60, method: 'popup'}],  # Override just reminders
  # title_template: nil,  # Use default from event type or global
  # color_id: nil         # Use default from event type or global
}
```

## Template System

### Liquid Templates

Templates use the [Liquid](https://shopify.github.io/liquid/) templating language for safe, sandboxed variable interpolation.

### Available Variables

When rendering templates, the following variables are available:

| Variable | Description | Example |
|----------|-------------|---------|
| `{{title}}` | Course title | "Computer Science I" |
| `{{course_code}}` | Full course code | "COMP-101-01" |
| `{{subject}}` | Subject code | "COMP" |
| `{{course_number}}` | Course number | "101" |
| `{{section_number}}` | Section number | "01" |
| `{{crn}}` | Course Reference Number | "12345" |
| `{{room}}` | Room number/name | "306" |
| `{{building}}` | Building name | "Wentworth Hall" |
| `{{location}}` | Full location string | "Wentworth Hall - 306" |
| `{{faculty}}` | Primary faculty name | "Dr. Smith" |
| `{{all_faculty}}` | All faculty names (comma-separated) | "Dr. Smith, Prof. Jones" |
| `{{start_time}}` | Formatted start time | "9:00 AM" |
| `{{end_time}}` | Formatted end time | "10:30 AM" |
| `{{day}}` | Day of week | "Monday" |
| `{{day_abbr}}` | Day abbreviation | "Mon" |
| `{{term}}` | Term name | "Spring 2024" |
| `{{schedule_type}}` | Schedule type | "lecture", "laboratory", "hybrid" |

### Template Examples

**Simple title templates:**
```liquid
{{course_code}}: {{title}}
→ "COMP-101-01: Computer Science I"

{{title}} ({{schedule_type}})
→ "Computer Science I (lecture)"

{{subject}} {{course_number}} - {{room}}
→ "COMP 101 - 306"
```

**Advanced templates with conditionals:**
```liquid
{{title}}{% if faculty %} - {{faculty}}{% endif %}
→ "Computer Science I - Dr. Smith"

{% if schedule_type == 'laboratory' %}Lab: {% endif %}{{title}}
→ "Lab: Computer Science I"

{{day_abbr}} {{start_time}}: {{title}}
→ "Mon 9:00 AM: Computer Science I"
```

**Description templates:**
```liquid
{{course_code}} - {{schedule_type | capitalize}}
Location: {{location}}
Instructor: {{faculty}}
Time: {{day}} {{start_time}} - {{end_time}}
```

## Reminder Settings

Reminders are stored as a JSONB array of reminder objects:

```json
[
  {
    "minutes": 30,
    "method": "popup"
  },
  {
    "minutes": 1440,
    "method": "email"
  }
]
```

**Fields:**
- `minutes` - Minutes before event to trigger reminder (integer)
- `method` - Reminder method: `popup` or `email` (Google Calendar API values)

**Common reminder times:**
- 15 minutes: `{minutes: 15, method: 'popup'}`
- 30 minutes: `{minutes: 30, method: 'popup'}`
- 1 hour: `{minutes: 60, method: 'popup'}`
- 1 day: `{minutes: 1440, method: 'email'}`
- 1 week: `{minutes: 10080, method: 'email'}`

## Color Settings

Google Calendar supports 11 color IDs (integers 1-11):

1. Lavender
2. Sage
3. Grape
4. Flamingo
5. Banana
6. Tangerine
7. Peacock
8. Graphite
9. Blueberry
10. Basil
11. Tomato

The existing `MeetingTime#event_color` method returns these based on schedule type, but preferences can override them.

## Preference Resolution

The `PreferenceResolver` service handles preference lookups and merging:

### Usage

```ruby
# For a meeting time
resolver = PreferenceResolver.new(user)
prefs = resolver.resolve_for(meeting_time)

# For a Google calendar event
prefs = resolver.resolve_for(google_calendar_event)

# Access resolved values
prefs[:title_template]       # => "{{course_code}}: {{title}}"
prefs[:reminder_settings]    # => [{minutes: 30, method: 'popup'}]
prefs[:color_id]            # => 7
```

### Resolution Algorithm

For each property (title_template, description_template, reminder_settings, color_id, visibility):

1. Check EventPreference for the specific event - if set, use it
2. Check CalendarPreference for event_type (if event has a type) - if set, use it
3. Check CalendarPreference for global scope - if set, use it
4. Fall back to system defaults

### System Defaults

If no preferences are configured:

**Title Template:**
- Laboratory: `{{title}} - Lab ({{room}})`
- Lecture: `{{course_code}}: {{title}}`
- Hybrid: `{{title}} [{{schedule_type}}]`
- Other: `{{title}}`

**Reminders:**
- `[{minutes: 15, method: 'popup'}]`

**Color:**
- Uses `MeetingTime#event_color` (existing logic based on schedule_type)

## Calendar Integration

Preferences are applied to both **Google Calendar sync** and **iCal feeds** for consistent event formatting across all calendar platforms.

### Google Calendar Sync Integration

The `GoogleCalendarService` uses resolved preferences when creating/updating events:

```ruby
# In GoogleCalendarService#create_event_in_calendar
def create_event_in_calendar(user, meeting_time)
  resolver = PreferenceResolver.new(user)
  prefs = resolver.resolve_for(meeting_time)

  # Render templates
  renderer = CalendarTemplateRenderer.new
  context = build_template_context(meeting_time)

  event_params = {
    summary: renderer.render(prefs[:title_template], context),
    description: renderer.render(prefs[:description_template], context),
    location: context[:location],
    start: { dateTime: start_time, timeZone: time_zone },
    end: { dateTime: end_time, timeZone: time_zone },
    recurrence: [recurrence_rule],
    reminders: {
      useDefault: false,
      overrides: prefs[:reminder_settings]
    },
    colorId: prefs[:color_id]&.to_s,
    visibility: prefs[:visibility]
  }

  # Create via Google Calendar API...
end
```

### iCal Feed Integration

The `CalendarsController` also uses resolved preferences when generating iCal feeds:

```ruby
# In CalendarsController#generate_ical
def generate_ical(courses)
  # Initialize preference resolver for this user
  @preference_resolver = PreferenceResolver.new(@user)
  @template_renderer = CalendarTemplateRenderer.new

  courses.each do |course|
    course.meeting_times.each do |meeting_time|
      # Resolve user preferences for this meeting time
      prefs = @preference_resolver.resolve_for(meeting_time)
      context = CalendarTemplateRenderer.build_context_from_meeting_time(meeting_time)

      # Apply title template
      event.summary = @template_renderer.render(prefs[:title_template], context)

      # Apply description template if set
      event.description = @template_renderer.render(prefs[:description_template], context)

      # Apply color preferences
      color_hex = get_google_color_hex(prefs[:color_id]) if prefs[:color_id].present?
      event.color = "##{color_hex}" if color_hex

      # ... rest of event creation
    end
  end
end
```

**Note:** iCal feeds are accessed via the calendar token:
- URL format: `/calendar/:calendar_token.ics`
- No authentication required (token acts as security)
- Feeds respect all user preferences
- Refreshed based on cache headers (1 hour)

## API Endpoints

### Global and Event-Type Preferences

**List all preferences for user:**
```http
GET /api/calendar_preferences
```

Response:
```json
{
  "global": {
    "title_template": "{{course_code}}: {{title}}",
    "reminder_settings": [{"minutes": 15, "method": "popup"}]
  },
  "event_types": {
    "lecture": {
      "title_template": "{{course_code}}: {{title}}",
      "color_id": 1
    },
    "laboratory": {
      "title_template": "{{title}} - Lab ({{room}})",
      "color_id": 7,
      "reminder_settings": [
        {"minutes": 30, "method": "popup"},
        {"minutes": 1440, "method": "email"}
      ]
    }
  }
}
```

**Update global preferences:**
```http
PUT /api/calendar_preferences/global
Content-Type: application/json

{
  "title_template": "{{day_abbr}} - {{title}}",
  "reminder_settings": [{"minutes": 30, "method": "popup"}]
}
```

**Update event-type preferences:**
```http
PUT /api/calendar_preferences/laboratory
Content-Type: application/json

{
  "title_template": "Lab: {{title}} in {{room}}",
  "color_id": 7
}
```

### Individual Event Preferences

**Get resolved preferences for a meeting time:**
```http
GET /api/meeting_times/42/preference
```

Response includes resolved values and their sources:
```json
{
  "resolved": {
    "title_template": "Lab: {{title}} in {{room}}",
    "reminder_settings": [{"minutes": 60, "method": "popup"}],
    "color_id": 7
  },
  "sources": {
    "title_template": "event_type:laboratory",
    "reminder_settings": "individual",
    "color_id": "event_type:laboratory"
  },
  "preview": "Lab: Computer Science I in 306"
}
```

**Set individual event override:**
```http
PUT /api/meeting_times/42/preference
Content-Type: application/json

{
  "reminder_settings": [
    {"minutes": 60, "method": "popup"}
  ]
}
```

### Template Preview

**Preview template rendering:**
```http
POST /api/calendar_preferences/preview
Content-Type: application/json

{
  "template": "{{day}} {{start_time}}: {{title}}",
  "meeting_time_id": 42
}
```

Response:
```json
{
  "rendered": "Wednesday 2:00 PM: Computer Science I",
  "valid": true
}
```

## Example Use Cases

### Use Case 1: Different Reminders for Same Course

Student has COMP-101 on Monday and Wednesday but wants different reminders:

1. Set event-type default for lectures: 15 minutes before
2. Override Wednesday meeting specifically: 1 hour before

```ruby
# Event type default (applies to all lectures)
CalendarPreference.create!(
  user: user,
  scope: 'event_type',
  event_type: 'lecture',
  reminder_settings: [{minutes: 15, method: 'popup'}]
)

# Individual override for Wednesday meeting
wednesday_meeting = MeetingTime.find_by(course: comp101, day_of_week: 'wednesday')
EventPreference.create!(
  user: user,
  preferenceable: wednesday_meeting,
  reminder_settings: [{minutes: 60, method: 'popup'}]
)
```

### Use Case 2: Custom Lab Titles with Room Numbers

Student wants lab titles to always show the room:

```ruby
CalendarPreference.create!(
  user: user,
  scope: 'event_type',
  event_type: 'laboratory',
  title_template: '{{title}} - Lab in {{room}}',
  color_id: 7
)
```

Result: "Computer Science I - Lab in 306"

### Use Case 3: Minimal Titles for Personal Calendar

Student prefers short titles for personal calendar viewing:

```ruby
CalendarPreference.create!(
  user: user,
  scope: 'global',
  title_template: '{{subject}} {{course_number}}'
)
```

Result: "COMP 101"

## Implementation Notes

### Template Validation

Templates are validated before saving:
- Must be valid Liquid syntax
- Only whitelisted variables allowed
- No filters that could execute arbitrary code

### Performance Considerations

- Preference resolution results can be cached per request
- Template rendering is fast but should be memoized during sync
- Use includes/joins when loading preferences to avoid N+1 queries

### Migration Strategy

For existing users:
1. System works without any preferences (uses system defaults)
2. Can optionally seed default preferences on user creation
3. UI can suggest templates based on popular patterns

## Future Enhancements

Potential additions to the system:

- **Preset Templates**: Library of popular template patterns users can choose from
- **Bulk Operations**: Apply preferences to multiple events at once
- **Import/Export**: Share preference configs between users
- **Smart Suggestions**: ML-based template suggestions based on usage patterns
- **Additional Variables**: GPA, credits, assignment due dates, etc.
- **Conditional Reminders**: Different reminders based on time of day or day of week
- **Notification Channels**: SMS, push notifications beyond Google Calendar
