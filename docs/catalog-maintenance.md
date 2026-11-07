# Catalog maintenance

The course catalog comes from Banner (LeopardWeb). These jobs and tasks keep it current. Every Banner request goes through `Catalog::BannerThrottle`. Jobs share a burst of 20 requests, then 5 a second. Web requests have their own burst of 60, then 10 a second, so a student's schedule never waits behind the nightly sync.

| What | When | How |
| --- | --- | --- |
| Import one term | A new term appears | Admin, Course catalog, Import (`Catalog::ImportJob`) |
| Nightly sync | Every night, current and future terms | `Catalog::CourseDataSyncJob` (`config/recurring.yml`) |
| Refresh one schedule's sections | After `POST /api/process_courses` serves sections from the catalog that Banner confirmed more than 6 hours ago | `Catalog::SectionRefreshJob` |
| Course details and prerequisites | After each import, and nightly | `Catalog::CourseDetailsSyncJob` |
| Re-import every term | After a change to the importer, or to find missed sections | `bin/rails catalog:reimport_all_terms` |
| Fetch every course's details again | After a new course detail column ships | `bin/rails catalog:backfill_course_details REFETCH=1` |

## Where a schedule's sections come from

`POST /api/process_courses` (`Courses::Processor`) does not ask Banner about a section that Banner confirmed in the last 36 hours. The nightly sync and each Banner fetch record that time in `courses.banner_synced_at`. Such a section comes from the catalog, and the request needs no Banner call. A new section, or one that the sync has not confirmed in 36 hours, goes to Banner as before. If the nightly sync stops, every section goes to Banner after 36 hours.

```mermaid
flowchart TD
  S[Section in the upload] --> F{In the catalog, and banner_synced_at in the last 36 h?}
  F -- yes --> C[Use the stored section]
  C --> O{Older than 6 h?}
  O -- yes --> J[Catalog::SectionRefreshJob asks Banner later]
  O -- no --> E[Enroll]
  J --> E
  F -- no --> B[Ask Banner now, write the section, set banner_synced_at]
  B --> E
```

Each request logs one line: `[Courses::Processor] user=… sections=… from_catalog=… from_banner=… refresh=… banner_ms=… total_ms=…`.

The Banner calls of a web request run inside a Puma thread, so these limits keep that thread short (#683):

- A payload can have at most `Courses::Processor::MAX_SECTIONS` (40) sections, counted as distinct CRN and term pairs. A larger payload gets a `400` before any Banner call. `POST /api/courses/reprocess` checks it before it removes an enrollment. In `POST /api/process_courses/batch`, the term fails.
- `Catalog::BannerThrottle::BUDGETS` sets the timeouts of each Banner request by caller. A web request waits 3 seconds to connect and 8 seconds to read. A job, a rake task, and the console wait 10 and 30 seconds.
- A web request that hits the read timeout fails at once. It does not retry, and it does not count toward the cooldown, so a slow Banner does not stop the jobs.

## When Banner cools down

After 5 failed Banner requests in a row, `Catalog::BannerThrottle` refuses every Banner request for 3 minutes and raises `CooldownError`. `Catalog::CourseDataSyncJob` and `Catalog::SectionRefreshJob` include `Catalog::BannerCooldownRetry`. On a cooldown, the job tries again after 3.5 minutes, plus up to 15% at random so that jobs do not all wake at the same time. It continues until a time window from its first attempt ends:

| Job | Window |
| --- | --- |
| `Catalog::CourseDataSyncJob` | 4 hours: the 4am run stops trying at about 8am |
| `Catalog::SectionRefreshJob` | 15 minutes |

At the end of the window, the job reports the `CooldownError` as handled and stops. It does not go to the failed list. The nightly sync syncs the sections confirmed longest ago first, so the next night continues the work.

The time of the first attempt stays in the job data. A retry from the admin page of a job whose window ended gets no new window, so it stops at its first cooldown.

Each retry is a new Solid Queue job, so the admin page shows it as a scheduled job that was enqueued seconds ago, with a retry count. That is a normal wait, not a stuck job.

## Course titles

Banner sends most course titles in capitals, for example `AGENTIC AI AND INTELLIGENT AGENTS`. `Course` formats each title when it is written (`normalizes :title`, with `Courses::TitleFormatter`). Code that reads a title uses it as it is.

- The formatter writes each word with a capital first letter, and writes Roman numerals in capitals: `Calculus II`. A word starts after a space, a hyphen, a slash, an opening parenthesis, an ampersand or a colon.
- It keeps each hyphen as Banner sends it: `CO-OP` becomes `Co-Op`. The one exception is a final lab: Banner fits a long title in 30 characters as `ANALY-LAB`, and the formatter writes ` - Lab`, because the default lab title template removes ` - Lab`.
- It writes the acronyms in `Courses::TitleFormatter::ACRONYMS` in capitals: `Agentic AI And Intelligent Agents`. It also writes degree program codes that start with `BS` in capitals: `BSCE/BSEN`. To add an acronym, add it to that list. Leave out acronyms that are also English words, such as IT and BE.
- It changes an HTML line break (`<br>`) between words to ` - `, and removes one at the start or end of a title.
- SQL that sets `title` directly skips the formatter. Write a title with `create`, `update`, or an assignment.

After a change to the formatter, format the stored titles again. The task needs no Banner request. It changes the current and future terms. Each changed course marks its students for a calendar sync and gets a new embedding.

```sh
bin/rails courses:normalize_titles

# Every term, past terms included.
ALL=1 bin/rails courses:normalize_titles
```

The formatter gives the same result when it runs again on a formatted title, so a second run of the task changes nothing.

`courses:normalize_titles` can only change a stored title. It cannot get back text that an older formatter removed, such as the spaces that it added around a hyphen (`Co - Op`). To get the titles from Banner again, run `courses:refresh_titles`. It sends one catalog request for each term, and each changed course marks its students for a calendar sync. The nightly sync also writes Banner titles again for the current and future terms.

```sh
# The current and next terms.
bin/rails courses:refresh_titles

# One term.
bin/rails "courses:refresh_titles[202710]"

# Every term that has courses, newest first.
ALL=1 bin/rails courses:refresh_titles
```

## Re-import every term

`catalog:reimport_all_terms` imports every term again from Banner, newest first, one term at a time. The current and future terms finish first.

```sh
# Print the plan: the terms it imports, and the terms it skips.
bin/rails catalog:reimport_all_terms DRY_RUN=1

# Import every term.
bin/rails catalog:reimport_all_terms

# Import only some terms (term uids, both ends included).
bin/rails catalog:reimport_all_terms FROM=202510 TO=202720
```

The task only queues `Catalog::ReimportAllTermsJob`. That job builds the plan, imports one term with `Catalog::ImportJob`, logs the result, and queues itself for the next term. Only one run goes at a time.

The plan has each term that Banner lists and that is in our database. It skips two kinds of term, and the log names them:

- A term that Banner lists but our database does not have. Create it on the admin course catalog page, then run the task again.
- A term in our database that Banner no longer lists. Banner has nothing to import for it.

### What a re-import changes

- It adds the sections that are missing and updates the ones that changed: title, credits, dates, link codes, and seats.
- It replaces the meeting times of a section whose times changed in Banner, the same as an import from the admin page.
- It deletes no section and changes no enrollment.
- Each import then queues the course details sync for its term. That sync skips the courses that already have fresh details.

### Follow it

Each term logs one line:

```text
[Catalog::ReimportAllTermsJob] Term 202720: 3 added, 41 updated, 1168 unchanged (28 terms left)
```

Search the logs for `Catalog::ReimportAllTermsJob`. A term that fails logs the error, is reported to `Rails.error`, and shows as failed on the admin course catalog page. The run goes on to the next term. To run one failed term again, use `FROM` and `TO` with that term's uid.

### How long it takes

- **Imports:** Banner lists every term back to 2014, about 39,500 sections. One import sends about 4 requests (a session and pages of 500 sections), so the Banner time is small. Most of the time is the database work, about 1 to 2 minutes for a term of 1,200 sections. All terms take about 30 to 60 minutes.
- **Course details:** each course details sync sends 8 requests for each course that needs new details (`LeopardWebClient::COURSE_DETAIL_PAGES`), at 5 requests a second. The newest terms take about 12 minutes each (450 courses). Older terms take less, because a course that a newer term already loaded is skipped. Expect a few hours in total, in the background, behind the imports.
