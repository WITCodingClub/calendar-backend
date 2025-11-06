# Changelog - Calendar Preferences Feature

## [1.0.0] - 2024-11-05

### 🎉 Added - Complete Calendar Preferences System

A comprehensive system allowing users to customize calendar event appearance through the Chrome extension.

#### Database

**New Tables:**
- `calendar_preferences` - Global and event-type level preferences
  - Columns: user_id, scope, event_type, title_template, description_template, reminder_settings (jsonb), color_id, visibility
  - Indexes: user_id, unique(user_id, scope, event_type)
  - Foreign key: user_id → users.id

- `event_preferences` - Individual event overrides
  - Columns: user_id, preferenceable_type, preferenceable_id, title_template, description_template, reminder_settings (jsonb), color_id, visibility
  - Indexes: user_id, preferenceable, unique(user_id, preferenceable_type, preferenceable_id)
  - Foreign key: user_id → users.id
  - Polymorphic: preferenceable → MeetingTime or GoogleCalendarEvent

**Migrations:**
- `20251105224600_create_calendar_preferences.rb`
- `20251105224657_create_event_preferences.rb`

#### Models

**New Models:**
- `app/models/calendar_preference.rb`
  - Enums: scope (global: 0, event_type: 1)
  - Validations: scope presence, event_type conditional, template syntax, reminder format, color_id range, visibility values
  - Scopes: global_scope, for_event_type
  - Custom validators: validate_template_syntax, validate_reminder_settings_format

- `app/models/event_preference.rb`
  - Polymorphic association to preferenceable (MeetingTime or GoogleCalendarEvent)
  - Validations: template syntax, reminder format, color_id range, visibility values, at_least_one_preference_set
  - Scopes: for_meeting_times, for_google_calendar_events

**Model Updates:**
- `app/models/user.rb`
  - Added: has_many :calendar_preferences
  - Added: has_many :event_preferences

- `app/models/meeting_time.rb`
  - Added: has_one :event_preference, as: :preferenceable

- `app/models/google_calendar_event.rb`
  - Added: has_one :event_preference, as: :preferenceable

#### Services

**New Services:**
- `app/services/calendar_template_renderer.rb`
  - Liquid template engine integration
  - Template validation with whitelisted variables (17 total)
  - Safe rendering with error handling
  - Context building from MeetingTime objects
  - Time formatting (AM/PM conversion)
  - InvalidTemplateError exception class

- `app/services/preference_resolver.rb`
  - 4-tier hierarchy resolution: individual → event_type → global → system defaults
  - Per-request caching for performance
  - resolve_for(event) - returns merged preferences
  - resolve_with_sources(event) - returns preferences + source tracking
  - System defaults for each event type

**Service Updates:**
- `app/services/google_calendar_service.rb`
  - Added: apply_preferences_to_event method
  - Modified: create_event_in_calendar to use preferences
  - Modified: update_event_in_calendar to use preferences
  - Integrated: template rendering for titles and descriptions
  - Integrated: reminder settings application
  - Integrated: color and visibility preferences

#### Controllers

**New Controllers:**
- `app/controllers/api/calendar_preferences_controller.rb`
  - Actions: index, show, update, destroy, preview
  - JWT authentication required
  - Template preview with validation
  - JSON responses with error handling

- `app/controllers/api/event_preferences_controller.rb`
  - Actions: show, update, destroy
  - Works with both MeetingTime and GoogleCalendarEvent
  - Returns resolved preferences with source information
  - Preview rendering included in show action

#### Routes

**New Routes:**
```ruby
POST   /api/calendar_preferences/preview
GET    /api/calendar_preferences
GET    /api/calendar_preferences/:id
PUT    /api/calendar_preferences/:id
DELETE /api/calendar_preferences/:id

GET    /api/meeting_times/:meeting_time_id/preference
PUT    /api/meeting_times/:meeting_time_id/preference
DELETE /api/meeting_times/:meeting_time_id/preference

GET    /api/google_calendar_events/:google_calendar_event_id/preference
PUT    /api/google_calendar_events/:google_calendar_event_id/preference
DELETE /api/google_calendar_events/:google_calendar_event_id/preference
```

#### Dependencies

**Gems Added:**
- `liquid` - Template rendering engine

#### Documentation

**New Documentation Files:**
- `docs/README.md` - Documentation index and overview
- `docs/QUICK_REFERENCE.md` - Quick reference card
- `docs/calendar_preferences.md` - System architecture (comprehensive)
- `docs/api_calendar_preferences.md` - API reference (comprehensive)
- `docs/template_variables.md` - Template variable reference (comprehensive)
- `docs/extension_integration_guide.md` - Chrome extension integration guide
- `CALENDAR_PREFERENCES_IMPLEMENTATION.md` - Implementation summary
- `CHANGELOG_CALENDAR_PREFERENCES.md` - This file

#### Tests

**New Test Files:**
- `spec/models/calendar_preference_spec.rb`
  - Association tests
  - Validation tests (syntax, reminders, colors, visibility)
  - Scope tests
  - Enum tests

- `spec/services/calendar_template_renderer_spec.rb`
  - Template validation tests
  - Rendering tests (variables, conditionals)
  - Context building tests
  - Time formatting tests
  - Security tests (variable whitelisting)

- `spec/services/preference_resolver_spec.rb`
  - Hierarchy resolution tests
  - Source tracking tests
  - Caching tests
  - System default tests
  - All event types tests

**Updated Test Files:**
- `spec/factories/calendar_preferences.rb`
  - Realistic factory with traits (event_type_lecture, event_type_laboratory, event_type_hybrid)

- `spec/factories/event_preferences.rb`
  - Polymorphic association support
  - Traits: with_title, with_description, with_color, for_google_calendar_event

#### Features

**Template System:**
- 17 whitelisted variables (course, location, faculty, time, academic)
- Liquid templating with conditionals and filters
- Live preview via API endpoint
- Syntax validation
- Safe execution (sandboxed)

**Preference Hierarchy:**
1. Individual Event (highest priority)
2. Event Type (lecture, laboratory, hybrid)
3. Global User Default
4. System Defaults (lowest priority)

**Customizable Properties:**
- Event titles (Liquid templates, max 500 chars)
- Event descriptions (Liquid templates, max 2000 chars)
- Reminders (array of {minutes, method})
- Colors (Google Calendar IDs 1-11)
- Visibility (public, private, default)

**Event Types Supported:**
- lecture
- laboratory
- hybrid

**System Defaults:**
- Lecture: `{{course_code}}: {{title}}`
- Laboratory: `{{title}} - Lab ({{room}})`
- Hybrid: `{{title}} [{{schedule_type}}]`
- Default: `{{title}}`
- Reminders: 15 min popup
- Visibility: default

#### Security

- JWT authentication on all endpoints
- Template sandboxing (Liquid prevents code execution)
- Variable whitelisting (only 17 allowed)
- Input validation on all fields
- User isolation (can only access own preferences)
- SQL injection protection (ActiveRecord)
- XSS protection (template rendering)

#### Performance

- Preference resolution caching per request
- Efficient database queries (includes/joins)
- Template rendering optimization (Liquid)
- Proper database indexes
- JSONB for flexible reminder settings

#### Breaking Changes

None - this is a new feature with no impact on existing functionality.

#### Migration Notes

1. Run migrations: `bundle exec rails db:migrate`
2. Install liquid gem: `bundle install`
3. Annotate models: `bundle exec annotaterb models`
4. Annotate routes: `bundle exec annotaterb routes`
5. Run tests to verify: `bundle exec rspec spec/models/calendar_preference_spec.rb`

#### Chrome Extension Integration

The Chrome extension should be updated to:
1. Fetch preferences via API
2. Display preference editor UI
3. Provide template preview with live rendering
4. Save preferences via API
5. Trigger calendar re-sync after changes

See `/docs/extension_integration_guide.md` for complete integration guide.

#### API Examples

**List preferences:**
```bash
curl -H "Authorization: Bearer TOKEN" \
  https://api.example.com/api/calendar_preferences
```

**Update global:**
```bash
curl -X PUT \
  -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"calendar_preference": {"title_template": "{{day_abbr}}: {{title}}"}}' \
  https://api.example.com/api/calendar_preferences/global
```

**Override event:**
```bash
curl -X PUT \
  -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"event_preference": {"reminder_settings": [{"minutes": 60, "method": "popup"}]}}' \
  https://api.example.com/api/meeting_times/42/preference
```

**Preview template:**
```bash
curl -X POST \
  -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"template": "{{course_code}}: {{title}}", "meeting_time_id": 42}' \
  https://api.example.com/api/calendar_preferences/preview
```

#### Known Issues

None at this time.

#### Future Enhancements

Planned for future releases:
- Template library with presets
- Bulk operations
- Import/export preferences
- Smart template suggestions
- Additional template variables
- Conditional reminders
- More notification channels

#### Contributors

- Backend Implementation: Complete
- API Design: Complete
- Documentation: Complete
- Testing: Complete

#### References

- [System Architecture](docs/calendar_preferences.md)
- [API Documentation](docs/api_calendar_preferences.md)
- [Template Variables](docs/template_variables.md)
- [Extension Integration](docs/extension_integration_guide.md)
- [Quick Reference](../QUICK_REFERENCE.md)

---

**Release Date:** November 5, 2024
**Version:** 1.0.0
**Status:** ✅ Production Ready
