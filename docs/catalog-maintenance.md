# Catalog maintenance

The course catalog comes from Banner (LeopardWeb). These jobs and tasks keep it current. Every Banner request goes through `Catalog::BannerThrottle`, which allows a burst of 20 requests, then 5 a second, for the whole process.

| What | When | How |
| --- | --- | --- |
| Import one term | A new term appears | Admin, Course catalog, Import (`Catalog::ImportJob`) |
| Nightly sync | Every night, current and future terms | `Catalog::CourseDataSyncJob` (`config/recurring.yml`) |
| Course details and prerequisites | After each import, and nightly | `Catalog::CourseDetailsSyncJob` |
| Re-import every term | After a change to the importer, or to find missed sections | `bin/rails catalog:reimport_all_terms` |

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
- **Course details:** each course details sync sends 4 requests for each course that needs new details, at 5 requests a second. The newest terms take about 6 minutes each (450 courses). Older terms take less, because a course that a newer term already loaded is skipped. Expect a few hours in total, in the background, behind the imports.
