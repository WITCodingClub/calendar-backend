# Term Date Management

## Overview

Terms now have `start_date` and `end_date` fields that are automatically calculated from their associated courses. This provides more accurate term identification and allows for date-based logic instead of relying solely on hard-coded season ranges.

## Database Schema

### Terms Table

- `start_date` (date, nullable) - Earliest start date from all courses in the term
- `end_date` (date, nullable) - Latest end date from all courses in the term

### Courses Table

- `start_date` (date, nullable) - Course start date from catalog
- `end_date` (date, nullable) - Course end date from catalog

## Date Parsing

Course dates are parsed from LeopardWeb API responses in `MM/DD/YYYY` format (e.g., `"01/06/2026"`):

```json
{
  "meetingTime": {
    "startDate": "01/06/2026",
    "endDate": "04/14/2026"
  }
}
```

The `CatalogImportService` extracts these dates from the first meeting time and parses them using `Date.strptime(date_string, "%m/%d/%Y")`.

## Automatic Updates

### Course Callbacks

The `Course` model automatically updates its associated term's dates when:

- A course is created with `start_date` or `end_date`
- A course's `start_date` or `end_date` is modified
- A course is destroyed

This ensures term dates stay synchronized with course data without manual intervention.

### Manual Updates

You can manually trigger a term date update:

```ruby
term.update_dates_from_courses!
```

This recalculates `start_date` and `end_date` from all associated courses.

## Term Identification

### Current Term Logic (Prioritized)

`Term.current` uses a four-tier approach:

1. **Active Term (Priority 1)**: Find term where today falls within `start_date` and `end_date`
   - Most accurate when courses have been imported
   - Example: Today is Oct 15, 2025 → finds Fall 2025 (Sep 2 - Dec 11)

2. **Past End Date → Next Term (Priority 2)**: If we're past a term's end_date, return the next term in sequence
   - Handles transition between semesters even if next term has no dates yet
   - Example: Today is Dec 22, 2025 (Fall ended Dec 11) → returns Spring 2026
   - Uses season progression: Fall → Spring (next year), Spring → Summer (same year), Summer → Fall (same year)

3. **Most Recent Started (Priority 3)**: Return the most recently started term
   - Handles long gaps (summer break) when next term is far away
   - Example: Today is June 1, 2025 (Spring ended, Fall starts Aug 15) → returns Spring 2025

4. **Season-Based Fallback (Priority 4)**: Uses hard-coded season ranges if no terms have dates
   - Spring: January 1 - May 31
   - Summer: June 1 - July 31
   - Fall: August 1 - December 31
   - Logs warning when used

### Next Term Logic (Prioritized)

`Term.next` uses a two-tier approach:

1. **Date-Based (Priority 1)**: Find the earliest term with a `start_date` after today
   - Most accurate when courses have been imported
   - Example: Today is Oct 15, 2025 → finds Spring 2026 (starts Jan 15, 2026)

2. **Season-Based Fallback (Priority 2)**: Uses season progression logic
   - Fall → Spring (next year)
   - Spring → Summer (same year)
   - Summer → Fall (same year)
   - Logs warning when used

### Why This Works in Production

**Crowdsourced Data Approach:**
- Each user who processes courses contributes to the term date accuracy
- User imports 5+ courses → their course dates update the term's aggregate dates
- First user to import gets approximate dates based on their courses
- Subsequent users refine the dates (earliest start_date, latest end_date across ALL courses)
- After ~10-20 users, term dates are highly accurate

**Example:**
```
User 1 imports: CS101 (Jan 15 - May 10), MATH201 (Jan 20 - May 5)
→ Term: Jan 15 - May 10

User 2 imports: ENGL102 (Jan 10 - May 12), PHYS150 (Jan 15 - May 8)
→ Term: Jan 10 - May 12  (expanded range)

User 3 imports: BUS200 (Jan 12 - May 15), CHEM101 (Jan 18 - May 10)
→ Term: Jan 10 - May 15  (final range gets more accurate)
```

## Helper Methods

### Instance Methods

```ruby
# Check if term is currently active (today is within start/end dates)
term.active?

# Check if term starts in the future
term.upcoming?

# Update term dates from courses
term.update_dates_from_courses!
```

### Class Methods

```ruby
# Get current term based on today's date
Term.current

# Get next term after current term
Term.next

# Get UIDs
Term.current_uid
Term.next_uid
```

## API Changes

### `/api/terms/current_and_next`

The endpoint now returns `start_date` and `end_date` for both current and next terms:

```json
{
  "current_term": {
    "name": "Fall 2025",
    "id": 202510,
    "pub_id": "trm_abc123",
    "start_date": "2025-08-15",
    "end_date": "2025-12-20"
  },
  "next_term": {
    "name": "Spring 2026",
    "id": 202620,
    "pub_id": "trm_def456",
    "start_date": "2026-01-15",
    "end_date": "2026-05-15"
  }
}
```

**Note**: `start_date` and `end_date` may be `null` if no courses exist for that term or if courses don't have date information.

## Migration

A database migration adds the new fields:

```ruby
class AddStartAndEndDateToTerms < ActiveRecord::Migration[8.1]
  def change
    safety_assured do
      change_table :terms, bulk: true do |t|
        t.date :start_date
        t.date :end_date
      end
    end
  end
end
```

### Backfilling Existing Data

To populate dates for existing terms:

```ruby
Term.find_each do |term|
  term.update_dates_from_courses! rescue nil
end
```

## Testing

Comprehensive test coverage includes:

- `spec/models/term_spec.rb` - Term date calculation, `active?`, `upcoming?`, current/next logic
- `spec/models/course_spec.rb` - Course callback behavior for automatic term date updates

Run tests:

```bash
bundle exec rspec spec/models/term_spec.rb
bundle exec rspec spec/models/course_spec.rb
```

## Benefits

1. **Accuracy**: Terms are identified by actual course dates, not hard-coded assumptions
2. **Flexibility**: Supports irregular term schedules (mini-mesters, accelerated courses)
3. **Automatic**: No manual intervention needed - dates update as courses are imported
4. **Backwards Compatible**: Falls back to season-based logic when dates aren't available
5. **API Enhancement**: Frontends can display actual term date ranges to users
