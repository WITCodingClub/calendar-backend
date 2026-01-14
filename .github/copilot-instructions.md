# Copilot Instructions for Calendar Backend

This Rails 8 application is an API backend that syncs college course schedules to Google Calendar with intelligent change detection, user preferences, and customizable calendar templates.

## Development Commands

### Running the Application
- `bin/dev` - Start web server, background jobs (Solid Queue), and CSS watcher
- `bin/rails server` - Start web server only
- `bin/rails solid_queue:start` - Start background job worker only
- `bin/rails console` - Start Rails console for debugging

### Database Operations
- `rails db:migrate` - Run pending migrations
- `bundle exec annotaterb models` - **REQUIRED after migrations** - Annotate model files with schema information
- `bundle exec annotaterb routes` - **REQUIRED after route changes** - Annotate routes.rb with route map

### Testing
- `bundle exec rspec` - Run all tests
- `bundle exec rspec spec/path/to/file_spec.rb` - Run specific test file
- **IMPORTANT: Maintain full RSpec test coverage for all new code**

### Code Quality
- `bundle exec rubocop` - Run linter
- `bundle exec rubocop -a` - Run linter with auto-fix
- `bundle exec brakeman` - Run security vulnerability scanner

### API Documentation
- `OPENAPI=1 bundle exec rspec spec/requests/api` - Generate OpenAPI/Swagger documentation from request specs
- Access docs at `/admin/api-docs` (requires admin login)
- **Automatic generation**: GitHub Actions automatically updates docs when API specs change on `main` branch

## Key Architectural Patterns

### Multi-Email OAuth Architecture
- Users can connect multiple Google accounts (school email, personal email, etc.)
- Single WIT Courses calendar is created via service account and shared with all user's connected emails
- Service account manages calendar operations; user OAuth credentials add calendar to their sidebar

### Intelligent Calendar Sync
- Hash-based change detection prevents unnecessary Google Calendar API calls
- Respects user edits made directly in Google Calendar (compares DB state with Google Calendar state)
- Three-tier preference system: Individual Event > Event Type (lecture/lab/hybrid) > Global > System Defaults

### Background Job Processing
- Use ActiveJob with Solid Queue (database-backed) for async operations
- **IMPORTANT: For anything that blocks threads, prefer using an ActiveJob**
- Common jobs: `GoogleCalendarSyncJob`, `CourseProcessorJob`, `NightlyCalendarSyncJob`

### Authorization System (Pundit)
- Role-based access control via User `access_level`: user/admin/super_admin/owner
- All controllers use `authorize @resource` to check permissions via policies in `app/policies/`
- See `docs/authorization.md` for complete documentation

## Important Development Guidelines

### Always Required
1. **Always annotate after migrations**: Run `bundle exec annotaterb models` after database changes
2. **Always annotate after route changes**: Run `bundle exec annotaterb routes` after modifying routes
3. **Full test coverage required**: Write RSpec tests for all new code
4. **Use Pundit authorization**: All controller actions must use `authorize @resource` to check permissions

### Code Style and Security
- Follow existing conventions and patterns in the codebase
- OAuth tokens must be encrypted with Lockbox
- Validate calendar preference templates (invalid syntax must be rejected)
- When bugfixing calendar features, fix both Google Calendar and ICS URL implementations

### Background Jobs
- Prefer background jobs for blocking operations (Google Calendar API calls, web scraping, etc.)
- Create jobs in `app/jobs/`
- Enqueue with `MyJob.perform_later(args)`
- Add specs in `spec/jobs/`

### Calendar Sync
- Respect user edits in Google Calendar (compare DB state with Google Calendar state)
- Use hash-based change detection to prevent unnecessary API calls
- Consider preference hierarchy: Individual Event > Event Type > Global > System Defaults

## Domain Models

### User & Authentication
- `User` - Core user model with access levels, uses email-based identification
- `Email` - Multiple emails per user (primary flag), enables multi-account OAuth
- `OauthCredential` - Encrypted OAuth tokens for Google Calendar
- Find/create users via `User.find_by_email(email_address)` or `User.find_or_create_by_email(email_address)`

### Course & Schedule Data
- `Course` - Course information with pgvector embeddings for semantic search
- `MeetingTime` - Individual class sessions with recurrence rules and event colors
- `Faculty` - Instructor information with Rate My Professor integration
- `Term` - Academic terms (Fall 2024, Spring 2025, etc.)

### Calendar Sync
- `GoogleCalendar` - Tracks the WIT Courses calendar (one per user's primary OAuth credential)
- `GoogleCalendarEvent` - Tracks individual events with hash-based change detection
- `CalendarPreference` - User preferences (global or per event type)
- `EventPreference` - Individual event overrides

## Service Layer
- `GoogleCalendarService` - All Google Calendar API operations (uses service account)
- `CalendarTemplateRenderer` - Liquid template rendering for event titles/descriptions
- `PreferenceResolver` - Resolves preference hierarchy for events
- `LeopardWebService` - Scrapes course data from college system

## Common Workflows

### Adding Authorization to Controllers
1. Add `authorize @resource` after finding/creating records
2. Use `policy_scope(Model)` to filter collections by user permissions
3. Create corresponding policy in `app/policies/` if it doesn't exist
4. Write RSpec tests in `spec/policies/` to verify permissions

### Adding/Updating API Endpoints
1. Create/update controller action in `app/controllers/api/`
2. Add request spec in `spec/requests/api/` - this generates the API docs
3. Test locally: `OPENAPI=1 bundle exec rspec spec/requests/api`
4. Docs auto-update on `main` branch via GitHub Actions

### Modifying Calendar Sync Logic
1. Update `GoogleCalendarService` methods
2. Consider hash-based change detection impact
3. Respect user edits detection logic
4. Add tests for new sync scenarios

## Documentation
- Main documentation is in the `/docs/` folder
- See `docs/README.md` for complete documentation map
- When building new features, update relevant docs

## Testing Guidelines
- Run linters, builds, and tests before making code changes to understand existing issues
- Only fix issues related to your task
- Test code changes as soon as possible after making them
- Run specific test suites for the area you're working on:
  - Authorization policies: `bundle exec rspec spec/policies/`
  - API endpoints: `bundle exec rspec spec/requests/api/`
  - Calendar preferences: `bundle exec rspec spec/models/calendar_preference_spec.rb`
  - Calendar sync: `bundle exec rspec spec/services/google_calendar_service_spec.rb`

## Additional Resources
For more detailed information, refer to:
- `CLAUDE.md` - Comprehensive AI agent instructions
- `docs/` - Detailed system documentation
- `docs/QUICK_REFERENCE.md` - Quick reference guide
