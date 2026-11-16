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
| `CourseCalendars` | Calendar sync for every provider: the provider base class with the sync loop, the provider registry, `CourseCalendars.resync`, the per-user lock and retry rules of the jobs, sync markers, the ICS feed (`docs/ics-feed.md`) |
| `GoogleCalendar` | Google Calendar: the OAuth client settings (`GoogleCalendar.config`, `.client_ids`), the remote calls of the provider, event labels, rate limits, calendar jobs |
| `MicrosoftGraph` | Microsoft Graph: the HTTP client, the remote calls of the provider, calendar jobs |
| `GoogleSignIn` | Google sign-in: token checks, code exchange, OAuth state, the grant revoke job |
| `MicrosoftSignIn` | Sign-in with a WIT Microsoft account |
| `OauthCredentials` | Account linking for every provider (`AccountLink`), token refresh and revoke jobs, the signed OAuth state, and the HTTP connection of the token calls (`Http`). `OauthCredential#refresh!` and `#mark_revoked!` hold the token rules |
| `Oauth` | The OAuth 2.1 server for MCP clients: consent page, client registration, metadata (`docs/mcp.md`) |
| `McpTools` | The MCP server, its tools, prompts, and apps (`docs/mcp.md`) |
| `McpPlatforms` | The addresses of hosted MCP clients, which skip the per-IP rate limits (`docs/mcp.md`) |
| `Risc` | Google RISC security events: the token check, the event handler, and the stream management client (`Risc::StreamClient`, used by the `risc:*` rake tasks). A token-revoked event names one refresh token: `Risc::TokenMatcher` finds its credential, and `OauthCredential#revoke_refresh_token!` deletes only that refresh token and sets the revoked flag. The credential row, its calendar and the person's sessions stay, because Google asks only to delete the token and to ask for consent again. A prefix that matches more than one credential revokes none (`token_ambiguous`). The other revoke events disconnect every Google credential of the person. An event with no Google account, such as a verification ping, is still recorded, with `SecurityEvent::UNKNOWN_SUBJECT` as its subject. `Risc::ProcessEventJob` retries an event that the handler could not record |
| `FriendMeetings`, `Friendships`, `FriendGroups`, `MeetingLinks` | Friends features |
| `Notifications` | Turning the reminders of every calendar event off and on |
| `Passkeys` | The passkey sign-in and registration ceremonies, and their `Passkeys::Failed` messages |
| `Faculties` | The faculty directory and RateMyProfessor |
| `FinalsSchedules` | Finals schedule PDFs, their parsers, and the rooms that an exam location names (`ExamRooms`) |
| `UniversityCalendar` | The university event calendar import: the category of a feed event (`Category`) and the match of a repeated event (`DuplicateMatcher`) |
| `Embeddings` | Vector embeddings |
| `Preferences` | Calendar preferences: resolution, versions, templates, colors, reminders. `PreferenceFields` lists the fields |
| `FeatureFlags` | Flipper flags, groups, and actors. Add a new flag to `FeatureFlags::DESCRIPTIONS` |
| `TwentyFiveLive` | 25Live: client, sync job, models, and value objects |
| `Cleanup`, `Database` | Maintenance jobs. `Cleanup::ExpiredRecordsJob` deletes the expired rows of each `Expirable` model |

Code with no domain stays at the root of its folder, for example `ApplicationService`, `JsonWebTokenService`, `AppMetrics`, `HttpFetcher` (every outside request with no client of its own: the importers, 25Live, the faculty photos, the Google RISC keys, the OpenAI address list, and GitHub releases), and `PdfText` (every PDF that an importer reads).

## Calendar providers

`CourseCalendars::Provider` owns everything that does not depend on the provider: the sync loop, the "edits in the calendar win" merge (`CourseCalendars::EventEdits`), the tracking rows, the duplicate race, the "event is gone, make it again" step, and the first sync of a new calendar (`#ensure_course_calendar`). `GoogleCalendar::Provider` and `MicrosoftGraph::CalendarProvider` subclass it and make only the remote calls. Each subclass also answers its own facts: who it syncs for, its OAuth start path, its auth, rate limit and transient errors, and a refused grant. Models, jobs and controllers reach a provider through `CourseCalendars::Providers`, never by a test of the provider name. A new provider is a new subclass and a new entry in `CourseCalendars::Providers::CLASSES`; the model provider lists, the job retry lists and the metrics read that list.

Every calendar connection ends in `OauthCredentials::AccountLink#connect!`: it saves the tokens, makes the course calendar, and starts one sync. Every other change that shapes a person's events starts its sync with `CourseCalendars.resync(user, force:)`, which queues nothing when no provider syncs for the person. The preference models (`CalendarPreference`, `EventPreference`, `UserExtensionConfig`) call it from one commit callback (`ResyncsCalendar`), so the API, the dashboard and the MCP tools never queue a sync for a preference. That covers a preference on any synced event, a university event or a final included. A row that a parent's destroy takes along does not sync. Changes that reach many users queue one bulk batch over `CourseCalendars::ResyncAudience`, which starts from `User.with_course_calendar`.

```mermaid
flowchart TD
  Syncer[CourseCalendars::ScheduleSyncer] --> Base[CourseCalendars::Provider: sync loop, edits, rows]
  Base --> Google[GoogleCalendar::Provider: Google API calls]
  Base --> Microsoft[MicrosoftGraph::CalendarProvider: Graph calls]
  Models[CalendarEvent, CourseCalendar, OauthCredential] --> Registry[CourseCalendars::Providers]
  Jobs[OauthCredentials::RefreshTokensJob, ProviderRetries] --> Registry
  Link[OauthCredentials::AccountLink] --> Registry
  Prefs[Preference models] --> Resync[CourseCalendars.resync]
  Resync --> SyncJob[CourseCalendars::SyncJob]
  Registry --> Google
  Registry --> Microsoft
```

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
- **Admin access:** `AdminAccess` lists the lowest access level of each admin section that needs more than admin access. The admin navigation, the policies (`CourseCatalogPolicy`, `ServiceAccountPolicy`), and the route constraints (`AdminConstraint.new(:jobs)`) read it. Add a new section there, not as a role test in a controller. `spec/policies/admin_access_spec.rb` checks that the three agree.
- **Fixed URLs:** the OAuth callbacks, `/risc/events`, and `/calendar/:token` never change. Google, Microsoft, and calendar apps store them.
- **Catalog pages:** the dashboard pages for courses, instructors, finals, and university events (#797) are read-only and open to every signed-in user. They include `Dashboard::CatalogPages`. The course and instructor pages use the `Catalog::` query objects and render the hashes of the `Catalog::` serializers, so they show the same data as the public catalog API. The finals and events pages use `FinalsSchedules::FinalExamQuery` and `UniversityCalendar::EventQuery`. Do not show a field there that the API leaves out, such as a faculty email. The prerequisite map on a course page (#448) comes from `Catalog::PrerequisiteGraph`. It walks the same prerequisites and unlocked courses that the API gives for each course, and `Dashboard::PrerequisiteGraphHelper` places the boxes.

The REST controllers, the GraphQL schema, and the MCP catalog tools also share the request layer. Each list query object (`Catalog::SectionQuery`, `CourseQuery`, `InstructorQuery`, `ReviewQuery`, `ProgramQuery`, `TermElectiveQuery`) declares its filters once (`Catalog::Filters`). The REST controllers read those filters from the request (`filter_params`; a string filter takes one value), `Types::CatalogFilterArguments` makes the GraphQL arguments from them, and `McpTools::CatalogFilters` makes the MCP input schema. `Catalog::ListRequest` runs a list: the query, the page (`Catalog::Page`), the total, and the serialized rows. The surfaces also share the filter readers (`Catalog::Params`), the term lookup (`Term.find_by_uid!`), and the section and instructor lookups (`Catalog::SectionQuery.find!`, `Catalog::InstructorQuery.find!`). The serializers and the GraphQL types read the values that take more than one column from `Catalog::Fields` and `Catalog::CourseRequisites`. Course codes have one owner, `CourseCode`: it parses a code to a key (`["COMP", 2350]`) and formats a key as a code, and a row with `subject_code` and `course_number` gets `key` and `code` from `CourseCode::Named`. A time of day is an HHMM integer (1350 is 13:50) with one owner, `Hhmm`: it parses, formats, and counts the minutes of a time. The checked aliases between codes have one owner, `AcademicProfiles::CourseKeys`. Prerequisite trees have one walker, `PrerequisiteTree`.

```mermaid
flowchart LR
  F0["Catalog::Filters on each query object"] --> L["Catalog::ListRequest"]
  F0 --> G
  F0 --> MCP
  L --> API
  L --> MCP
  P["Catalog::Page, Catalog::Params"] --> L
  P --> G["/api/v1/graphql"]
  Q["Catalog:: query objects"] --> S["Catalog:: serializers"]
  Q --> G
  F["Catalog::Fields, Catalog::CourseRequisites"] --> S
  F --> G
  S --> API["/api/v1/catalog (public API)"]
  S --> MCP["MCP catalog tools"]
  S --> D["/dashboard/courses and /dashboard/instructors"]
```

## Shared actions

An action that the API, the dashboard and an MCP tool all offer lives in one service. Each surface finds the record, authorizes it with the same policy, calls the service, and renders the result its own way (JSON, a redirect, or a tool result). Do not copy the rules of an action into a controller or a tool.

```mermaid
flowchart LR
  API["Api:: controller"] --> S["Service: Notifications::Toggle, Friendships::Request,<br/>MeetingLinks::Removal, OauthCredentials::Disconnect,<br/>Friendships::Removal, Passkeys::Authentication, Passkeys::Registration"]
  D["Dashboard:: controller"] --> S
  M["McpTools:: tool"] --> S
  S --> Models
```

- **Flags:** a controller gates a feature with `require_feature FeatureFlags::X, "message"` (`FeatureGate`). An API controller answers 404 in the JSON error format, a dashboard controller an empty 404. `DegreePlanningFlag` and `FriendGroupsFlag` name the two gates that many controllers share. The friends flags are read with `Friendships::Features`.

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
