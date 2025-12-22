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

### Current Term Logic

`Term.current` uses a two-tier approach:

1. **Date-based (preferred)**: Finds the term where today falls within `start_date` and `end_date`
2. **Season-based (fallback)**: Uses hard-coded season ranges if no terms have dates set:
   - Spring: January 1 - May 31
   - Summer: June 1 - July 31
   - Fall: August 1 - December 31

### Next Term Logic

`Term.next` also uses a two-tier approach:

1. **Date-based (preferred)**: Finds the earliest term with a `start_date` after today
2. **Season-based (fallback)**: Uses season progression logic:
   - Fall → Spring (next year)
   - Spring → Summer (same year)
   - Summer → Fall (same year)

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
