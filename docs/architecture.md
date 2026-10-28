# Code organization

This page gives the rules for where code goes. Issue #710 set them. Follow them for new code.

## Rules

1. **Group by domain.** A domain's services, jobs, value objects, and errors share one module in every folder. For example, `FriendMeetings::Creator` is in `app/services/friend_meetings/creator.rb`, and `FriendMeetings::PublishJob` is in `app/jobs/friend_meetings/publish_job.rb`.
2. **Keep models, policies, and mailers flat.** The database stores model class names (polymorphic types, Solid Queue job arguments), and Pundit finds a policy from the model name. `Course::MeetingTime` and `TwentyFiveLive::*` are the only nested models.
3. **Use the plural for a domain namespace:** `Courses::`, `Faculties::`, `Friendships::`. A singular name such as `Faculty::` makes the `Faculty` model a namespace.
4. **Do not use a namespace that a gem owns.** The Google gems define `Google::Auth` and `Google::Apis`, so the app uses `GoogleSignIn::` and `GoogleCalendar::`. Flipper owns `Flipper::`, so the app uses `FeatureFlags::`. PgHero owns `PgHero::`, so its jobs are in `Database::`.
5. **Name a class after what it does.** Inside a namespace, a service has no `Service` suffix: `Courses::Processor`, not `CourseProcessorService`. A class that only sends HTTP requests to an outside system is a `Client`.
6. **Keep an error in the namespace that raises it:** `Courses::InvalidTermError`, `Catalog::FilterError`.
7. **Define a namespaced class inside its modules:** `module Admin` and then `class UsersController`, not `class Admin::UsersController`. RuboCop checks this with `Style/ClassAndModuleChildren`.

## Domains

| Namespace | What it holds |
|---|---|
| `Catalog` | The course catalog: import, snapshot, LeopardWeb client, queries, serializers, semantic search (upkeep: `docs/catalog-maintenance.md`) |
| `DegreeRequirements` | The academic catalog import: programs, plans of study, elective lists, and course descriptions for each catalog year (`docs/degree-requirements.md`) |
| `TermElectives` | The elective list PDFs that each school publishes for a term (`docs/term-electives.md`) |
| `Courses` | A user's course list: enrollments, processed events |
| `AcademicProfiles` | A student's level, class standing, and programs from LeopardWeb (`docs/academic-profile.md`) |
| `CourseOutcomes` | The outcome of each finished course, without the letter grade (`docs/academic-profile.md`) |
| `CourseCalendars` | Calendar sync for every provider: sync jobs, provider selection, sync markers, the ICS feed |
| `GoogleCalendar` | Google Calendar: the provider, event labels, colors, rate limits, calendar jobs |
| `MicrosoftGraph` | Microsoft Graph: the HTTP client, the calendar provider, calendar jobs |
| `GoogleSignIn` | Google sign-in and account linking: token checks, code exchange, OAuth state |
| `MicrosoftSignIn` | Sign-in with a WIT Microsoft account |
| `OauthCredentials` | Token refresh and revoke for every provider |
| `Oauth` | The OAuth 2.1 server for MCP clients: consent page, client registration, metadata (`docs/mcp.md`) |
| `McpTools` | The MCP server, its tools, prompts, and apps (`docs/mcp.md`) |
| `McpPlatforms` | The addresses of hosted MCP clients, which skip the per-IP rate limits (`docs/mcp.md`) |
| `Risc` | Google RISC security events |
| `FriendMeetings`, `Friendships`, `MeetingLinks` | Friends features |
| `Faculties` | The faculty directory and RateMyProfessor |
| `FinalsSchedules` | Finals schedule PDFs and their parsers |
| `UniversityCalendar` | The university event calendar import |
| `Embeddings` | Vector embeddings |
| `Preferences` | Calendar preferences: resolution, versions, templates |
| `FeatureFlags` | Flipper flags, groups, and actors |
| `TwentyFiveLive` | 25Live: client, sync job, models, and value objects |
| `Cleanup`, `Database` | Maintenance jobs |

Code with no domain stays at the root of its folder, for example `ApplicationService`, `JsonWebTokenService`, and `AppMetrics`.

## Controllers and routes

```mermaid
flowchart TD
  R[config/routes.rb] --> auth[routes/auth.rb]
  R --> site[routes/site.rb]
  R --> feeds[routes/feeds.rb]
  R --> webhooks[routes/webhooks.rb]
  R --> api[routes/api.rb]
  R --> dashboard[routes/dashboard.rb]
  R --> admin[routes/admin.rb]
  api --> catalog[routes/api/catalog.rb]
  api --> user[routes/api/user.rb]
  api --> friends[routes/api/friends.rb]
  api --> calendar[routes/api/calendar.rb]
  api --> legacy[routes/api/legacy.rb]
  auth --> Auth["Auth:: controllers"]
  feeds --> Feeds["Feeds:: controllers"]
  webhooks --> Webhooks["Webhooks:: controllers"]
  api --> Api["Api:: controllers<br/>(one Api::BaseController)"]
  dashboard --> Dashboard["Dashboard:: controllers"]
  admin --> Admin["Admin:: controllers"]
```

- **API route files:** `routes/api.rb` draws each file in `routes/api/` inside `namespace :api`. Put a new API route in the file for its area. The catch-all route stays last in `routes/api.rb`.
- **API:** every API controller inherits from `Api::BaseController`. `CLAUDE.md` has the rules for auth, errors, and old paths.
- **Fixed URLs:** the OAuth callbacks, `/risc/events`, and `/calendar/:token` never change. Google, Microsoft, and calendar apps store them.

## Views

Issue #699 set these rules for the dashboard and the sign-in pages. The admin pages use the partials in `app/views/admin/shared/`.

- **Shared partials** live in `app/views/shared/`. Use them before you write the markup again:

  | Partial | Use |
  |---|---|
  | `page_header` | The title of a page, with an optional `back:` link, `description:`, and actions in the block |
  | `back_link` | A link back to the parent page, when the page has no `page_header` |
  | `section_card` | A card with a titled header. The block is the body |
  | `list_link_row` | One link row with a title, a hint, and a chevron |
  | `empty_state` | A card for a list with no items. The block holds the next step |
  | `status_card` | The result card of the OAuth and passkey pages |

- **Icons:** call `icon(:name, css_class: "w-4 h-4")` from `IconHelper`. Add a new icon to `IconHelper::ICONS` (outline) or `FILLED_ICONS`. Do not paste an inline `<svg>`. `logo_mark(:small)`, `(:medium)`, or `(:large)` draws the logo.
- **Page widths:** wrap each dashboard page in one width class. `m3-page-narrow` is for one form or a few settings, `m3-page-medium` is for lists of records, and `m3-page-wide` is for calendars.
- **Buttons and badges:** use the `m3-btn-*` and `m3-badge-*` classes in `app/assets/tailwind/application.css`. `m3-btn-provider` is the sign-in button for Google, Microsoft, and passkeys.
- **JavaScript:** put page code in a Stimulus controller, not an inline script. Shared modules live in `app/javascript/lib/`, for example `lib/webauthn`.

## Renaming a job

Solid Queue stores job class names in the database. `CLAUDE.md` ("Jobs") gives the steps: a fixed `CONCURRENCY_GROUP`, an alias file at the old path, and `bin/rails jobs:unknown_class_names` before the alias goes.
