# Rate My Professor Integration

This document describes how the Rate My Professor (RMP) integration works in the Calendar Backend application.

## Overview

The RMP integration allows the application to fetch and store professor ratings from RateMyProfessors.com. The system:
- Stores individual ratings for detailed analysis
- Automatically matches professors to their RMP profiles
- Tracks related professors and can link them to existing faculty records
- Runs as a background job to avoid blocking requests

## Architecture

### Models

#### 1. Faculty (`app/models/faculty.rb`)
The main professor model with RMP integration.

**New Fields:**
- `rmp_id` (string, unique, nullable) - The Rate My Professor ID (format: `VGVhY2hlci0yMjI1ODA2`)

**Associations:**
- `has_many :rmp_ratings` - Individual ratings from RMP
- `has_many :related_professors` - Related professors suggested by RMP
- `has_one :rating_distribution` - Rating distribution (r1-r5 counts)
- `has_many :teacher_rating_tags` - Rating tags with counts

**Key Methods:**
- `update_ratings!` - Enqueue background job to update ratings
- `update_ratings_now!` - Update ratings synchronously
- `calculate_rating_stats` - Calculate aggregate statistics from stored ratings
- `matched_related_faculty` - Get related professors that exist in the database
- `Faculty.update_all_ratings!` - Update ratings for all faculty (class method)

#### 2. RMPRating (`app/models/rmp_rating.rb`)
Stores individual ratings from Rate My Professor.

**Fields:**
- `faculty_id` (bigint, required) - Foreign key to Faculty
- `rmp_id` (string, required, unique) - RMP legacy ID for the rating
- `clarity_rating` (integer) - How clear the professor is (1-5)
- `difficulty_rating` (integer) - Course difficulty (1-5)
- `helpful_rating` (integer) - How helpful the professor is (1-5)
- `course_name` (string) - Course code (e.g., "MATH1875")
- `comment` (text) - Student review text
- `rating_date` (datetime) - When the rating was posted
- `grade` (string) - Grade received (e.g., "A-", "Not sure yet")
- `would_take_again` (boolean, nullable) - Would take this professor again
- `attendance_mandatory` (string) - "mandatory", "non-mandatory", etc.
- `is_for_credit` (boolean) - Taken for credit
- `is_for_online_class` (boolean) - Online class
- `rating_tags` (text) - Tags like "Tough grader--Lots of homework"
- `thumbs_up_total` (integer, default: 0) - Upvotes on the rating
- `thumbs_down_total` (integer, default: 0) - Downvotes on the rating

**Scopes:**
- `recent` - Order by rating_date descending
- `positive` - clarity_rating >= 4
- `negative` - clarity_rating <= 2

**Methods:**
- `overall_sentiment` - Returns "positive", "negative", or "neutral"

#### 3. RelatedProfessor (`app/models/related_professor.rb`)
Tracks professors that RMP suggests as related/similar.

**Fields:**
- `faculty_id` (bigint, required) - The faculty this is related to
- `rmp_id` (string, required) - RMP ID of the related professor
- `first_name` (string)
- `last_name` (string)
- `avg_rating` (decimal)
- `related_faculty_id` (bigint, nullable) - If matched to existing Faculty record

**Methods:**
- `try_match_faculty!` - Attempts to match this related professor to an existing Faculty record by rmp_id
- `full_name` - Returns "FirstName LastName"

#### 4. RatingDistribution (`app/models/rating_distribution.rb`)
Stores the distribution of ratings (how many 1-star, 2-star, etc. ratings).

**Fields:**
- `faculty_id` (bigint, required, unique) - Foreign key to Faculty (one-to-one relationship)
- `r1` (integer, default: 0) - Number of 1-star ratings
- `r2` (integer, default: 0) - Number of 2-star ratings
- `r3` (integer, default: 0) - Number of 3-star ratings
- `r4` (integer, default: 0) - Number of 4-star ratings
- `r5` (integer, default: 0) - Number of 5-star ratings
- `total` (integer, default: 0) - Total number of ratings

**Methods:**
- `percentage(level)` - Calculate percentage for a specific rating level (1-5)
- `percentages` - Get all percentages as a hash

**Example:**
```ruby
faculty.rating_distribution.percentage(5)
# => 13.16  (meaning 13.16% of ratings are 5-star)

faculty.rating_distribution.percentages
# => { r1: 36.84, r2: 26.32, r3: 5.26, r4: 18.42, r5: 13.16 }
```

#### 5. TeacherRatingTag (`app/models/teacher_rating_tag.rb`)
Stores rating tags (e.g., "Tough grader", "Lots of homework") with their occurrence counts.

**Fields:**
- `faculty_id` (bigint, required) - Foreign key to Faculty
- `rmp_legacy_id` (integer, required) - RMP legacy ID for the tag
- `tag_name` (string, required) - Name of the tag (e.g., "Tough grader")
- `tag_count` (integer, default: 0) - Number of times this tag was applied

**Validations:**
- Unique `rmp_legacy_id` per faculty
- `tag_count` must be >= 0

**Scopes:**
- `ordered_by_count` - Order by tag_count descending
- `top_tags(limit = 5)` - Get top N tags

**Example:**
```ruby
faculty.teacher_rating_tags.top_tags
# => [
#   #<TeacherRatingTag tag_name: "Tough grader", tag_count: 21>,
#   #<TeacherRatingTag tag_name: "Lots of homework", tag_count: 15>,
#   #<TeacherRatingTag tag_name: "Test heavy", tag_count: 12>,
#   ...
# ]
```

### Service Layer

#### RateMyProfessorService (`app/services/rate_my_professor_service.rb`)
Handles all API communication with RateMyProfessors.com GraphQL API.

**Constants:**
- `BASE_URL` - "https://www.ratemyprofessors.com/graphql"
- `WENTWORTH_SCHOOL_ID` - "U2Nob29sLTExNTg=" (base64 encoded school ID)

**Methods:**

##### `search_professors(name, school_id: WENTWORTH_SCHOOL_ID, count: 10)`
Search for professors by name at a specific school.

**Parameters:**
- `name` - Full name or partial name to search
- `school_id` - School ID (defaults to Wentworth)
- `count` - Number of results to return

**Returns:** Hash with search results including teacher basic info

##### `get_teacher_details(teacher_id)`
Fetch detailed information about a specific teacher.

**Parameters:**
- `teacher_id` - RMP teacher ID (e.g., "VGVhY2hlci0yMjI1ODA2")

**Returns:** Hash with teacher details including:
- Basic info (name, department, school)
- Aggregate stats (avgRating, avgDifficulty, numRatings, wouldTakeAgainPercent)
- First 20 ratings
- Related teachers
- Rating tags
- Course codes

##### `get_ratings(teacher_id, count: 100, cursor: nil)`
Fetch a page of ratings for a teacher.

**Parameters:**
- `teacher_id` - RMP teacher ID
- `count` - Number of ratings per page (default: 100)
- `cursor` - Pagination cursor from previous response

**Returns:** Hash with ratings page and pagination info

##### `get_all_ratings(teacher_id)`
**Automatically paginate through ALL ratings** for a teacher.

**Parameters:**
- `teacher_id` - RMP teacher ID

**Returns:** Array of all rating objects

**Note:** This method handles pagination automatically and will make multiple API requests if needed.

### Background Job

#### UpdateFacultyRatingsJob (`app/jobs/update_faculty_ratings_job.rb`)
ActiveJob that fetches and stores RMP data for a faculty member.

**Queue:** `:default`

**Workflow:**
1. Find the Faculty record by ID
2. If no `rmp_id` exists, search RMP and match by first AND last name
3. Fetch teacher details from RMP
4. Store rating distribution (r1-r5 counts)
5. Store teacher rating tags with counts
6. Store all related professors
7. Fetch and store ALL individual ratings (with automatic pagination)
8. Attempt to match related professors to existing Faculty records

**Matching Logic:**
- Searches for up to 10 results on RMP
- Finds exact match where BOTH first name AND last name match (case-insensitive)
- Only links if both names match exactly

**Error Handling:**
- Returns early if professor not found on RMP
- Skips invalid ratings gracefully
- Logs success with rating count

## Usage

### Basic Usage

```ruby
# Update ratings for a single faculty member (async - recommended)
faculty = Faculty.find_by(email: "professor@example.edu")
faculty.update_ratings!

# Update ratings synchronously (blocks until complete)
faculty.update_ratings_now!

# Update all faculty ratings in the background
Faculty.update_all_ratings!
```

### Querying Ratings

```ruby
faculty = Faculty.find_by(first_name: "Mami", last_name: "Wentworth")

# Get all ratings
faculty.rmp_ratings
# => #<ActiveRecord::Associations::CollectionProxy [...]>

# Get recent ratings
faculty.rmp_ratings.recent.limit(5)

# Get positive ratings
faculty.rmp_ratings.positive

# Get negative ratings
faculty.rmp_ratings.negative

# Count ratings
faculty.rmp_ratings.count
# => 38
```

### Calculating Statistics

```ruby
faculty.calculate_rating_stats
# => {
#   avg_rating: 2.5,
#   avg_difficulty: 3.9,
#   num_ratings: 38,
#   would_take_again_percent: 34.21
# }

# Check if faculty has ratings
faculty.rmp_ratings.any?
```

### Working with Rating Distribution

```ruby
# Get rating distribution
dist = faculty.rating_distribution

# Get counts for each star level
dist.r1  # => 14 (number of 1-star ratings)
dist.r2  # => 10
dist.r3  # => 2
dist.r4  # => 7
dist.r5  # => 5
dist.total  # => 38

# Get percentages
dist.percentage(1)  # => 36.84
dist.percentages
# => { r1: 36.84, r2: 26.32, r3: 5.26, r4: 18.42, r5: 13.16 }
```

### Working with Teacher Rating Tags

```ruby
# Get all rating tags
faculty.teacher_rating_tags

# Get top 5 most common tags
faculty.teacher_rating_tags.top_tags
# => [
#   #<TeacherRatingTag tag_name: "Tough grader", tag_count: 21>,
#   #<TeacherRatingTag tag_name: "Lots of homework", tag_count: 15>,
#   ...
# ]

# Get all tags ordered by count
faculty.teacher_rating_tags.ordered_by_count

# Find a specific tag
faculty.teacher_rating_tags.find_by(tag_name: "Tough grader")
```

### Working with Related Professors

```ruby
# Get all related professors
faculty.related_professors

# Get only those matched to existing Faculty records
faculty.matched_related_faculty

# Manually try to match a related professor
related_prof = faculty.related_professors.first
related_prof.try_match_faculty!
```

### Direct Service Usage

```ruby
service = RateMyProfessorService.new

# Search for a professor
results = service.search_professors("John Smith")

# Get teacher details
teacher_id = "VGVhY2hlci0yMjI1ODA2"
details = service.get_teacher_details(teacher_id)

# Get all ratings
ratings = service.get_all_ratings(teacher_id)
```

## Data Flow

```
1. User/System calls faculty.update_ratings!
                    ↓
2. UpdateFacultyRatingsJob enqueued
                    ↓
3. Job checks if faculty has rmp_id
   - No: Search RMP and match by first+last name
   - Yes: Skip to step 4
                    ↓
4. Fetch teacher details from RMP
                    ↓
5. Store rating distribution (r1-r5 counts)
                    ↓
6. Store teacher rating tags with counts
                    ↓
7. Store related professors (with auto-matching)
                    ↓
8. Fetch ALL ratings via pagination
                    ↓
9. Store each rating (find_or_initialize_by rmp_id)
                    ↓
10. Log completion
```

## Database Schema

### Faculties Table
```sql
Column      | Type      | Modifiers
------------|-----------|----------
rmp_id      | string    | unique index
```

### RMP Ratings Table
```sql
Column               | Type      | Modifiers
---------------------|-----------|----------
faculty_id           | bigint    | not null, indexed, foreign key
rmp_id               | string    | not null, unique index
clarity_rating       | integer   |
difficulty_rating    | integer   |
helpful_rating       | integer   |
course_name          | string    |
comment              | text      |
rating_date          | datetime  |
grade                | string    |
would_take_again     | boolean   |
attendance_mandatory | string    |
is_for_credit        | boolean   |
is_for_online_class  | boolean   |
rating_tags          | text      |
thumbs_up_total      | integer   | default: 0
thumbs_down_total    | integer   | default: 0
```

### Related Professors Table
```sql
Column             | Type           | Modifiers
-------------------|----------------|----------
faculty_id         | bigint         | not null, indexed, foreign key
rmp_id             | string         | not null
first_name         | string         |
last_name          | string         |
avg_rating         | decimal(3,2)   |
related_faculty_id | bigint         | nullable, indexed, foreign key

Unique index: [faculty_id, rmp_id]
```

### Rating Distributions Table
```sql
Column     | Type    | Modifiers
-----------|---------|----------
faculty_id | bigint  | not null, unique index, foreign key
r1         | integer | default: 0
r2         | integer | default: 0
r3         | integer | default: 0
r4         | integer | default: 0
r5         | integer | default: 0
total      | integer | default: 0

Note: One-to-one relationship with Faculty
```

### Teacher Rating Tags Table
```sql
Column        | Type    | Modifiers
--------------|---------|----------
faculty_id    | bigint  | not null, indexed, foreign key
rmp_legacy_id | integer | not null
tag_name      | string  | not null
tag_count     | integer | default: 0

Unique index: [faculty_id, rmp_legacy_id]
```

## Notes

- All indexes use `algorithm: :concurrently` for safe production deployments
- Foreign keys are added without validation (`validate: false`) to avoid blocking writes
- The job uses `find_or_initialize_by` to avoid duplicate ratings
- RMP IDs are stored as strings (base64 encoded GraphQL node IDs)
- Rating dates are parsed from ISO 8601 format
- The integration gracefully handles missing or null data from RMP

## Future Enhancements

Potential improvements:
- [ ] Add fuzzy name matching for better professor matching
- [ ] Cache RMP data with TTL to reduce API calls
- [ ] Add rate limiting to respect RMP's API
- [ ] Schedule periodic updates for all faculty
- [ ] Add webhooks/callbacks for rating updates
- [ ] Implement retry logic with exponential backoff
- [ ] Add metrics/monitoring for job success rates
- [x] Store rating distribution data (r1-r5 counts) ✅
- [x] Store teacher rating tags with counts ✅
