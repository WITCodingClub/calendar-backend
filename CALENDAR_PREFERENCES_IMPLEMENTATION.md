# Calendar Preferences System - Implementation Summary

## ✅ Implementation Complete

A complete hierarchical event configuration system has been implemented for the calendar backend.

## 📋 What Was Built

### Database Layer

**Two new tables created:**

1. **`calendar_preferences`** - Global and event-type level preferences
   - Stores user defaults for all events or specific event types (lecture, laboratory, hybrid)
   - Fields: title_template, description_template, reminder_settings, color_id, visibility
   - Unique constraint on `[user_id, scope, event_type]`

2. **`event_preferences`** - Individual event overrides
   - Polymorphic association to MeetingTime or GoogleCalendarEvent
   - Same preference fields (all nullable for partial overrides)
   - Unique constraint on `[user_id, preferenceable_type, preferenceable_id]`

**Migrations:**
- `db/migrate/20251105224600_create_calendar_preferences.rb`
- `db/migrate/20251105224657_create_event_preferences.rb`

### Models

**Created:**
- `app/models/calendar_preference.rb` - Validations, enums, scopes
- `app/models/event_preference.rb` - Validations, polymorphic associations

**Updated:**
- `app/models/user.rb` - Added associations to calendar_preferences and event_preferences
- `app/models/meeting_time.rb` - Added polymorphic event_preference association
- `app/models/google_calendar_event.rb` - Added polymorphic event_preference association

### Services

**Created:**

1. **`app/services/calendar_template_renderer.rb`**
   - Uses Liquid templating engine for safe variable interpolation
   - Validates templates (syntax + whitelisted variables only)
   - Renders templates with context from meeting times
   - 17 available variables (title, course_code, room, faculty, times, etc.)

2. **`app/services/preference_resolver.rb`**
   - Implements 4-tier hierarchy: individual → event_type → global → system defaults
   - Caches results per request for performance
   - Provides `resolve_for` and `resolve_with_sources` methods

**Updated:**
- `app/services/google_calendar_service.rb` - Integrated preferences into event creation/update
- `app/controllers/calendars_controller.rb` - Integrated preferences into iCal feed generation

### API Controllers

**Created:**

1. **`app/controllers/api/calendar_preferences_controller.rb`**
   - `GET /api/calendar_preferences` - List all preferences
   - `GET /api/calendar_preferences/:id` - Get specific preference (global or event type)
   - `PUT /api/calendar_preferences/:id` - Create/update preference
   - `DELETE /api/calendar_preferences/:id` - Delete preference
   - `POST /api/calendar_preferences/preview` - Preview template rendering

2. **`app/controllers/api/event_preferences_controller.rb`**
   - `GET /api/meeting_times/:id/preference` - Get event preference with resolution
   - `PUT /api/meeting_times/:id/preference` - Update event override
   - `DELETE /api/meeting_times/:id/preference` - Delete event override
   - Same endpoints for `/api/google_calendar_events/:id/preference`

### Routes

Added to `config/routes.rb`:
```ruby
namespace :api do
  resources :calendar_preferences, only: [:index, :show, :update, :destroy] do
    collection do
      post :preview
    end
  end

  resources :meeting_times, only: [] do
    resource :preference, controller: 'event_preferences', only: [:show, :update, :destroy]
  end

  resources :google_calendar_events, only: [] do
    resource :preference, controller: 'event_preferences', only: [:show, :update, :destroy]
  end
end
```

### Documentation

**Created comprehensive documentation:**

1. **`/docs/README.md`** - Documentation index and overview
2. **`/docs/calendar_preferences.md`** - Complete system architecture and implementation
3. **`/docs/api_calendar_preferences.md`** - API reference with examples and workflows
4. **`/docs/template_variables.md`** - Complete template variable reference
5. **`/docs/extension_integration_guide.md`** - Chrome extension integration guide

### Tests

**Created comprehensive test coverage:**

1. **`spec/models/calendar_preference_spec.rb`**
   - Association tests
   - Validation tests (syntax, reminder format, color IDs, etc.)
   - Scope tests
   - Enum tests

2. **`spec/services/calendar_template_renderer_spec.rb`**
   - Template validation tests
   - Rendering tests with variables and conditionals
   - Context building tests
   - Time formatting tests

3. **`spec/services/preference_resolver_spec.rb`**
   - Hierarchy resolution tests
   - Source tracking tests
   - Caching tests
   - System default tests

4. **Updated factories:**
   - `spec/factories/calendar_preferences.rb` - Realistic test data with traits
   - `spec/factories/event_preferences.rb` - Polymorphic association support

## 🎯 Key Features

### Hierarchical Configuration
```
Individual Event Override
    ↓ (if not set)
Event Type Preference
    ↓ (if not set)
Global User Preference
    ↓ (if not set)
System Defaults
```

### Template System
- **Engine:** Liquid (safe, sandboxed)
- **Variables:** 17 available (course info, location, faculty, time, term)
- **Features:** Conditionals, case statements, filters
- **Validation:** Syntax checking + whitelist enforcement

### Customizable Properties
- ✅ Event titles (Liquid templates)
- ✅ Event descriptions (Liquid templates)
- ✅ Reminders (multiple per event, popup/email)
- ✅ Colors (Google Calendar color IDs 1-11)
- ✅ Visibility (public/private/default)

### Calendar Integration
- ✅ **Google Calendar Sync** - Full preference support in GoogleCalendarService
- ✅ **iCal Feeds** - Preferences applied to .ics exports
- ✅ **Consistent Formatting** - Same templates used across all calendar platforms

## 📊 Database Schema

### CalendarPreference
```sql
CREATE TABLE calendar_preferences (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id),
  scope INTEGER NOT NULL,  -- 0=global, 1=event_type
  event_type VARCHAR,       -- 'lecture', 'laboratory', 'hybrid', etc.
  title_template TEXT,
  description_template TEXT,
  reminder_settings JSONB DEFAULT '[]',
  color_id INTEGER,
  visibility VARCHAR,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL,

  UNIQUE(user_id, scope, event_type)
);
```

### EventPreference
```sql
CREATE TABLE event_preferences (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id),
  preferenceable_type VARCHAR NOT NULL,  -- 'MeetingTime' or 'GoogleCalendarEvent'
  preferenceable_id BIGINT NOT NULL,
  title_template TEXT,
  description_template TEXT,
  reminder_settings JSONB,
  color_id INTEGER,
  visibility VARCHAR,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL,

  UNIQUE(user_id, preferenceable_type, preferenceable_id)
);
```

## 🔌 API Usage Examples

### Set Global Default
```bash
curl -X PUT https://api.example.com/api/calendar_preferences/global \
  -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "calendar_preference": {
      "title_template": "{{day_abbr}} {{start_time}}: {{title}}",
      "reminder_settings": [{"minutes": 15, "method": "popup"}]
    }
  }'
```

### Override Individual Event
```bash
curl -X PUT https://api.example.com/api/meeting_times/42/preference \
  -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "event_preference": {
      "reminder_settings": [{"minutes": 60, "method": "popup"}]
    }
  }'
```

### Preview Template
```bash
curl -X POST https://api.example.com/api/calendar_preferences/preview \
  -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "template": "{{course_code}}: {{title}} in {{room}}",
    "meeting_time_id": 42
  }'

# Response:
{
  "rendered": "COMP-101-01: Computer Science I in 306",
  "valid": true
}
```

## 🚀 Deployment Steps

1. **Install dependencies:**
   ```bash
   bundle install
   ```

2. **Run migrations:**
   ```bash
   bundle exec rails db:migrate
   ```

3. **Annotate models and routes:**
   ```bash
   bundle exec annotaterb models
   bundle exec annotaterb routes
   ```

4. **Run tests:**
   ```bash
   bundle exec rspec spec/models/calendar_preference_spec.rb
   bundle exec rspec spec/models/event_preference_spec.rb
   bundle exec rspec spec/services/calendar_template_renderer_spec.rb
   bundle exec rspec spec/services/preference_resolver_spec.rb
   ```

5. **Verify API endpoints:**
   ```bash
   bundle exec rails routes | grep calendar_preferences
   bundle exec rails routes | grep event_preferences
   ```

## 🎨 Example Use Cases

### Use Case 1: Global Title Format
User wants all events to show day and time:
```liquid
{{day_abbr}} {{start_time}}: {{title}}
→ "Mon 9:00 AM: Computer Science I"
```

### Use Case 2: Lab-Specific Titles
User wants labs to always show room numbers:
```liquid
{{title}} - Lab ({{room}})
→ "Computer Science I - Lab (306)"
```

### Use Case 3: Different Reminders per Day
User wants different reminder times for Wednesday class:
- Global: 15 min before
- Wednesday override: 60 min before

### Use Case 4: Color Coding
User wants different colors per event type:
- Lectures: Lavender (1)
- Labs: Peacock (7)
- Hybrid: Graphite (8)

## 🔒 Security Features

- ✅ JWT authentication required for all endpoints
- ✅ Templates sandboxed (Liquid prevents code execution)
- ✅ Only whitelisted variables allowed
- ✅ Input validation on all fields
- ✅ Users can only access/modify their own preferences
- ✅ SQL injection protection (ActiveRecord)
- ✅ XSS protection (template rendering)

## 📈 Performance Optimizations

- ✅ Preference resolution caching per request
- ✅ Efficient database queries (includes/joins to prevent N+1)
- ✅ Template rendering is fast (Liquid is optimized)
- ✅ Indexes on all lookup columns
- ✅ JSONB for flexible reminder settings

## 🧪 Testing

Run all preference-related tests:
```bash
bundle exec rspec spec/models/calendar_preference_spec.rb
bundle exec rspec spec/models/event_preference_spec.rb
bundle exec rspec spec/services/calendar_template_renderer_spec.rb
bundle exec rspec spec/services/preference_resolver_spec.rb
```

## 📱 Chrome Extension Integration

The Chrome extension should:
1. Fetch preferences via `GET /api/calendar_preferences`
2. Display current settings in UI
3. Allow users to edit templates with live preview
4. Save changes via `PUT /api/calendar_preferences/:id`
5. Trigger calendar re-sync after changes

See `/docs/extension_integration_guide.md` for complete integration guide.

## 🔄 System Integration

### How It Works

1. User configures preferences in Chrome extension
2. Extension saves via API endpoints
3. When calendar syncs (Google Calendar) or iCal feed is requested:
   - `GoogleCalendarService` creates/updates events (for Google Calendar sync)
   - `CalendarsController` generates iCal feed (for iCal subscriptions)
   - For each event, `PreferenceResolver` walks hierarchy
   - `CalendarTemplateRenderer` renders templates
   - Formatted events sent to Google Calendar API or included in iCal feed

### Data Flow
```
Chrome Extension (UI)
    ↓ (API calls)
Rails Backend (API Controllers)
    ↓ (saves to)
Database (calendar_preferences, event_preferences)
    ↓ (read during sync/feed generation)
PreferenceResolver (resolves hierarchy)
    ↓ (provides context)
CalendarTemplateRenderer (renders templates)
    ↓ (formats events)
    ├─→ GoogleCalendarService (creates events)
    │       ↓ (syncs to)
    │   Google Calendar API
    │
    └─→ CalendarsController (generates iCal)
            ↓ (serves)
        iCal Feed (.ics file)
```

## 🎓 Learning Resources

For developers working with this system:

1. **Backend Developers:**
   - Read `/docs/calendar_preferences.md` for architecture
   - Study `CalendarTemplateRenderer` and `PreferenceResolver` services
   - Understand Liquid templating: https://shopify.github.io/liquid/

2. **Extension Developers:**
   - Start with `/docs/extension_integration_guide.md`
   - Reference `/docs/api_calendar_preferences.md` for API details
   - Check `/docs/template_variables.md` for available variables

3. **Everyone:**
   - `/docs/README.md` has overview and quick links
   - Run tests to understand behavior
   - Check out example templates in documentation

## 📞 Support

- Documentation: `/docs/` directory
- Issues: Open on GitHub repository
- Questions: Contact backend development team

## ✨ Future Enhancements

Potential additions being considered:

- [ ] Template library with presets
- [ ] Bulk operations (apply to multiple events)
- [ ] Import/export preference configs
- [ ] Smart template suggestions (ML-based)
- [ ] Additional variables (GPA, credits, assignments)
- [ ] Conditional reminders (different by time/day)
- [ ] More notification channels (SMS, push)
- [ ] Template versioning/history
- [ ] Sharing templates between users
- [ ] Advanced analytics on preference usage

## 🎉 Summary

A complete, production-ready calendar preferences system has been implemented with:
- ✅ Full database schema with migrations
- ✅ Models with validations and associations
- ✅ Service layer with template rendering and preference resolution
- ✅ RESTful API with 8 endpoints
- ✅ Comprehensive documentation (5 docs)
- ✅ Test coverage for core functionality
- ✅ Security measures and performance optimizations
- ✅ Chrome extension integration guide

The system is ready for use and can be extended as needed!

---

**Implementation Date:** November 2024
**Status:** ✅ Production Ready
**Version:** 1.0.0
