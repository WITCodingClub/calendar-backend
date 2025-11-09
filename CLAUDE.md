# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Running the Application
- `bin/dev` - Start web server, background jobs (Solid Queue), and CSS watcher
- `bin/rails server` - Start web server only
- `bin/rails solid_queue:start` - Start background job worker only
- `bin/rails tailwindcss:watch` - Start CSS watcher only
- `bin/rails console` - Start Rails console for debugging

### Database Operations
- `rails db:create` - Create database
- `rails db:migrate` - Run pending migrations
- `rails db:seed` - Seed database with initial data
- `rails db:reset` - Drop, create, migrate, and seed database
- `bundle exec annotaterb models` - **REQUIRED after migrations** - Annotate model files with schema information
- `bundle exec annotaterb routes` - **REQUIRED after route changes** - Annotate routes.rb with route map

### Testing
- `bundle exec rspec` - Run all tests
- `bundle exec rspec spec/path/to/file_spec.rb` - Run specific test file
- `bundle exec rspec spec/path/to/file_spec.rb:42` - Run specific test at line 42
- **IMPORTANT: Maintain full RSpec test coverage for all code**

### Code Quality
- `bundle exec rubocop` - Run linter
- `bundle exec rubocop -a` - Run linter with auto-fix
- `bundle exec brakeman` - Run security vulnerability scanner

## Architecture Overview

### Core Purpose
A Rails 8 API backend that syncs college course schedules to Google Calendar with intelligent change detection, user preferences, and customizable calendar templates.

### Key Architectural Patterns

**Multi-Email OAuth Architecture**
- Users can connect multiple Google accounts (school email, personal email, etc.)
- Single WIT Courses calendar is created via service account and shared with all user's connected emails
- Service account manages calendar operations; user OAuth credentials add calendar to their sidebar
- See `app/models/concerns/google_oauthable.rb` and `docs/calendar-sync/multi-email-google-calendar-oauth.md`

**Intelligent Calendar Sync**
- Hash-based change detection prevents unnecessary Google Calendar API calls
- Respects user edits made directly in Google Calendar (compares DB state with Google Calendar state)
- Three-tier preference system: Individual Event > Event Type (lecture/lab/hybrid) > Global > System Defaults
- See `app/services/google_calendar_service.rb` and `docs/calendar-sync/intelligent_calendar_sync.md`

**Background Job Processing**
- Use ActiveJob with Solid Queue (database-backed) for async operations
- **IMPORTANT: For anything that blocks threads, prefer using an ActiveJob**
- Common jobs: `GoogleCalendarSyncJob`, `CourseProcessorJob`, `NightlyCalendarSyncJob`
- Monitor jobs at `/admin/jobs` (Mission Control)

**Calendar Preferences System**
- Liquid templating for customizable event titles/descriptions (17 template variables available)
- Per-event-type or per-event customization (color, reminders, visibility, templates)
- Validated templates prevent breaking changes
- See `docs/calendar-preferences/` for complete documentation

**Security & Encryption**
- OAuth tokens encrypted with Lockbox
- Rate limiting with Rack::Attack
- Audit logging with Audits1984 and Console1984
- Admin access via Google OAuth + access_level enum (user/admin/super_admin/owner)

**Authorization System (Pundit)**
- Role-based access control via User `access_level`: user/admin/super_admin/owner
- **user** (0): Can manage their own resources only
- **admin** (1): VIEW all resources for support, manage public data (courses/faculty), NO destructive actions
- **super_admin** (2): View AND modify all resources, perform destructive actions, access feature flags. **Cannot delete owners**
- **owner** (3): Full access including managing other admins
- Three policy categories: User-Owned (users manage their own), Public-Read (everyone reads, admins manage), Admin-Only (admins view only)
- All controllers use `authorize @resource` to check permissions via policies in `app/policies/`
- See `docs/authorization.md` for complete documentation

### Domain Models

**User & Authentication**
- `User` - Core user model with access levels, uses email-based identification
- `Email` - Multiple emails per user (primary flag), enables multi-account OAuth
- `OauthCredential` - Encrypted OAuth tokens for Google Calendar (supports multiple credentials per user)
- Users found via `User.find_by_email(email_address)` or created via `User.find_or_create_by_email(email_address)`

**Course & Schedule Data**
- `Course` - Course information with pgvector embeddings for semantic search
- `MeetingTime` - Individual class sessions with recurrence rules and event colors
- `Faculty` - Instructor information with Rate My Professor integration
- `Term` - Academic terms (Fall 2024, Spring 2025, etc.)
- `Building`, `Room` - Location data

**Calendar Sync**
- `GoogleCalendar` - Tracks the WIT Courses calendar (one per user's primary OAuth credential)
- `GoogleCalendarEvent` - Tracks individual events with hash-based change detection
- `CalendarPreference` - User preferences (global or per event type)
- `EventPreference` - Individual event overrides

### Service Layer
- `GoogleCalendarService` - All Google Calendar API operations (uses service account)
- `CalendarTemplateRenderer` - Liquid template rendering for event titles/descriptions
- `PreferenceResolver` - Resolves preference hierarchy for events
- `LeopardWebService` - Scrapes course data from college system
- `RateMyProfessorService` - Fetches professor ratings
- `JsonWebTokenService` - JWT authentication for API endpoints

### API Authentication
- JWT-based authentication for all `/api/*` endpoints
- Include `Authorization: Bearer <token>` header
- See `app/controllers/concerns/json_web_token_authenticatable.rb`

### Feature Flags
- Flipper for feature toggling
- Beta tester management at `/admin/beta_testers`
- Check features with `Features.enabled?(:feature_name, user)`
- See `app/lib/features.rb`

## Documentation
- **IMPORTANT: I document systems and things in the `/docs/` folder**
- See `docs/README.md` for complete documentation map
- Quick reference: `docs/QUICK_REFERENCE.md`
- When building new features, update relevant docs

## Important Development Notes

1. **Always annotate after migrations**: Run `bundle exec annotaterb models` after database changes
2. **Always annotate after route changes**: Run `bundle exec annotaterb routes` after modifying routes
3. **Prefer background jobs**: Use ActiveJob for blocking operations (Google Calendar API calls, web scraping, etc.)
4. **Full test coverage required**: Write RSpec tests for all new code
5. **Use Pundit authorization**: All controller actions must use `authorize @resource` to check permissions
6. **Respect user edits**: The calendar sync intelligently detects and preserves user modifications in Google Calendar
7. **Template validation**: Calendar preference templates are validated; invalid syntax is rejected
8. **OAuth token encryption**: All sensitive tokens are encrypted with Lockbox
9. **Multi-email support**: Design features to support users with multiple connected Google accounts

## Common Development Workflows

### Adding a New Background Job
1. Create job in `app/jobs/`
2. Enqueue with `MyJob.perform_later(args)`
3. Add specs in `spec/jobs/`
4. See `docs/infrastructure/job-queues.md`

### Modifying Calendar Sync Logic
1. Update `GoogleCalendarService` methods
2. Consider hash-based change detection impact
3. Respect user edits detection logic
4. Add tests for new sync scenarios
5. See `docs/calendar-sync/intelligent_calendar_sync.md`

### Adding Template Variables
1. Update `CalendarTemplateRenderer.build_context_from_meeting_time`
2. Document in `docs/calendar-preferences/template_variables.md`
3. Add validation tests
4. Update preview endpoint tests

### Adding Authorization to Controllers
1. Add `authorize @resource` after finding/creating records
2. Use `policy_scope(Model)` to filter collections by user permissions
3. Create corresponding policy in `app/policies/` if it doesn't exist
4. Write RSpec tests in `spec/policies/` to verify permissions
5. See `docs/authorization.md` for policy patterns

### Running Tests for Specific Features
- Authorization policies: `bundle exec rspec spec/policies/`
- Calendar preferences: `bundle exec rspec spec/models/calendar_preference_spec.rb`
- Template rendering: `bundle exec rspec spec/services/calendar_template_renderer_spec.rb`
- Preference resolution: `bundle exec rspec spec/services/preference_resolver_spec.rb`
- Google Calendar sync: `bundle exec rspec spec/services/google_calendar_service_spec.rb`
- always make and follow pundit policies
- thread blocking operations are ok, just not prefered where ever possible