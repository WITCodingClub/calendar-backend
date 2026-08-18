# Public Catalog API

A read-only API for the WIT course schedule. It needs no authentication and no
API key.

The API has two surfaces over the same data:

| Surface | Endpoint | Use it for |
| --- | --- | --- |
| REST | `GET /api/v1/catalog/...` | Simple requests, caching, curl |
| GraphQL | `POST /api/graphql` | One request for nested data |

Both surfaces use the same filter object, `Catalog::SectionQuery`. A filter
gives the same result on both.

```mermaid
flowchart LR
    R[REST controllers] --> Q[Catalog::SectionQuery]
    G[GraphQL QueryType] --> Q
    Q --> DB[(courses)]
    R --> S[Catalog serializers]
    G --> T[Types::*]
```

## What the API contains

The API contains course schedule data only:

- Terms, subjects, and course sections
- Meeting days, times, buildings, and rooms
- Instructors, with Rate My Professors scores
- Final exam times

The API contains no user data. It does not return student records, grades, or
enrollments. It does not return instructor email addresses, phone numbers, or
office locations.

## Limits

- Responses are public and cacheable for 1 hour.
- Rate limit: 300 requests per minute per IP address.
- REST page size: 50 by default, 200 maximum.
- GraphQL page size: 50 by default, 200 maximum.
- GraphQL query depth: 12 maximum. Query complexity: 500 maximum.
- GraphQL has no mutations.

## REST

### Response shape

A collection returns `data` and `meta`:

```json
{
  "data": [ ... ],
  "meta": { "page": 1, "per_page": 50, "total_count": 1174, "total_pages": 24 }
}
```

A single record returns `data` only.

An error returns `error` and `code`:

```json
{ "error": "Unknown day \"funday\"", "code": "INVALID_FILTER" }
```

The code is `INVALID_FILTER` (HTTP 400) or `NOT_FOUND` (HTTP 404).

### Endpoints

| Method and path | Description |
| --- | --- |
| `GET /api/v1/catalog/terms` | All terms, newest first |
| `GET /api/v1/catalog/terms/:uid` | One term by its Banner code, e.g. `202710` |
| `GET /api/v1/catalog/subjects` | Subjects with section counts |
| `GET /api/v1/catalog/sections` | Sections, with filters |
| `GET /api/v1/catalog/sections/:crn` | One section by CRN |
| `GET /api/v1/catalog/instructors` | Faculty who teach at least one section |
| `GET /api/v1/catalog/instructors/:pub_id` | One instructor |

`GET /api/v1/catalog/subjects` accepts `term_uid`.

`GET /api/v1/catalog/instructors` accepts `term_uid`, `q`, `page`, and
`per_page`.

`GET /api/v1/catalog/sections/:crn` accepts `term_uid`. Use it when one CRN
occurs in more than one term. This endpoint also returns cancelled sections, so
a saved CRN does not disappear without an explanation.

### Section filters

All filters are optional. Give a list as a comma-separated value, for example
`subject=COMP,MATH`.

| Filter | Example | Effect |
| --- | --- | --- |
| `term_uid` | `202710` | Keep sections in this term |
| `subject` | `COMP` | Match the code or the full label |
| `course_number` | `1000` | Keep these course numbers |
| `crn` | `10001,10002` | Keep these CRNs |
| `pub_id` | `crs_kw7coe30` | Keep these sections by public id |
| `q` | `algorithms` | Search the title, subject, and number |
| `schedule_type` | `lecture` or `LEC` | Keep these schedule types |
| `credit_hours` | `4` | Keep these credit hours |
| `instructor` | `byron` | Match the instructor name |
| `meets_on` | `monday,friday` | Keep sections that meet on any of these days |
| `free_days` | `friday` | Drop sections that meet on any of these days |
| `begins_after` | `10:00` | Drop sections with any meeting before this time |
| `ends_before` | `16:00` | Drop sections with any meeting after this time |
| `include_cancelled` | `true` | Add cancelled sections |
| `page`, `per_page` | `2`, `100` | Page through the result |

`begins_after` and `ends_before` accept `HH:MM` or `HHMM`. Both are inclusive at
the boundary.

`free_days`, `begins_after`, and `ends_before` apply to the whole section. A
section is dropped if **any** of its meetings breaks the rule. This is what a
student wants: one Friday afternoon lab still ruins a free Friday.

An unknown filter value returns HTTP 400. An unknown query parameter is ignored.

### Example

Find Computer Science sections in Fall 2026 that keep Friday free and do not
start before 10:00:

```bash
curl "https://calendar.witcc.dev/api/v1/catalog/sections?term_uid=202710&subject=COMP&free_days=friday&begins_after=10:00"
```

## GraphQL

Send a POST request to `/api/graphql` with a JSON body:

```bash
curl -X POST https://calendar.witcc.dev/api/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "{ terms { uid name sectionCount } }"}'
```

Send variables as JSON, not as strings. A form-encoded request turns every
value into a string, and GraphQL then rejects booleans and numbers.

### Queries

| Query | Arguments | Returns |
| --- | --- | --- |
| `terms` | — | All terms, newest first |
| `term` | `uid` | One term |
| `subjects` | `termUid` | Subjects with section counts |
| `sections` | `filter`, plus Relay arguments | A connection of sections |
| `section` | `crn`, `termUid` | One section, cancelled ones included |
| `instructors` | `termUid`, `q`, plus Relay arguments | A connection of faculty |

`sections` and `instructors` are Relay connections. Both add `totalCount`, so a
client can show "50 of 1174" without a second request.

The `filter` argument takes the same filters as REST, in camelCase. Days and
schedule types are enums, for example `FRIDAY` and `LECTURE`, so a wrong value
fails at validation time.

### Example

One request for a section and everything attached to it:

```graphql
{
  section(crn: 17294) {
    courseCode
    title
    creditHours
    term { uid name }
    meetingTimes {
      day
      beginTime
      endTime
      durationMinutes
      location { display building { abbreviation name } rooms { number floor } }
    }
    instructors { name rmp { avgRating numRatings } }
    linked { required identifier crns pubIds }
    finalExam { date startTime endTime location }
  }
}
```

Filter with variables:

```graphql
query Sections($filter: SectionFilterInput) {
  sections(filter: $filter, first: 50) {
    totalCount
    pageInfo { hasNextPage endCursor }
    nodes { crn courseCode title }
  }
}
```

```json
{ "filter": { "termUid": 202710, "subject": ["COMP"], "freeDays": ["FRIDAY"] } }
```

## Notes on the data

- `seats.capacity` and `seats.available` come from Banner. The catalog import
  sets them, and a nightly job refreshes them for every active term. They can be
  up to a day old, so do not show them as a real-time seat count. Responses also
  carry `Cache-Control: public, max-age=3600`, which adds at most one more hour.
  Either field is `null` when Banner did not return enrollment data for the CRN.
- `linked` says which sections a student must register together, most often a
  lecture and its lab. It comes from Banner's own `linkIdentifier`, which reads
  as `<slot><key>`: the first character is the slot (`A` for the lecture, `B`
  for the lab) and the rest is the key that pairs them. A lecture `A1` goes with
  every lab `B1` of the same course. `linked.crns` lists the partners in the
  same term, so a client does not have to work the pairing out from the section
  number. `linked.pub_ids` names the same partners by public id, in the same
  order. `linked.required` is `false` and both lists are empty for a section
  that stands alone.
- `pub_id` is the id to store. It is unique across every term and it never
  changes, so it is the key to use when you join this catalog to another system.
  A CRN is only unique inside one term, and the registrar reuses it. Both are
  filters: `pub_id` needs no term, `crn` normally does. A `pub_id` that does not
  decode is a 400, not an empty result.
- `location` is `null` when a section has no room, as with online sections.
  `location.display` is `null` when the room is a placeholder "TBD" record.
- `rmp` is `null` when an instructor has no ratings. Rate My Professors reports
  "no data" as `0` for an average and `-1` for a percentage. The API removes
  these sentinel numbers so a client never shows them as real scores.
- Duplicate meeting rows from a repeated import are collapsed. The copy with a
  real room wins.

## Dump the GraphQL schema

```bash
bin/rails runner 'puts CatalogSchema.to_definition' > catalog.graphql
```
