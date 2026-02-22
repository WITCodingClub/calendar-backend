# Prerequisite System Architecture

## Research Summary

### Data Source: catalog.wit.edu

**URL Pattern**: `https://catalog.wit.edu/course-descriptions/[dept]/`

Where `[dept]` is lowercase department code (comp, math, chem, etc.)

### Prerequisite Formatting Patterns

Based on analysis of Computer Science, Mathematics, and Chemistry catalogs:

#### 1. HTML Structure
- Prerequisites appear in `<em>` or `<i>` tags at end of course descriptions
- Course codes are hyperlinked: `<a href="/search/?P=COMP1000">COMP1000</a>`
- Label format: "Prerequisite:" (singular) or "Prerequisites:" (plural)
- Corequisite format: "Corequisite:" followed by course code

#### 2. Logical Operators
- **AND**: Expressed as " and " or ", " or "; " between course codes
  - Examples:
    - "COMP2000 and COMP2350 and MATH2100"
    - "MATH1800, MATH1850, MATH1877"
- **OR**: Expressed as " or " between course codes
  - Examples:
    - "COMP1000 or ELEC3150"
    - "MATH1877 or MATH1875"
- **Mixed**: Semicolon separates distinct requirement groups
  - Example: "COMP1050; MATH2300 or MATH2800" (requires COMP1050 AND (MATH2300 OR MATH2800))

#### 3. Grade Requirements
- Format: "course_code completed with a grade of X or better"
- Example: "MATH2100 completed with a grade of B or better"
- Grades: A, B, C, D (standard letter grades)

#### 4. Special Prerequisites
- **Placement**: "MATH Placement" or "MATH1000 or MATH Placement"
- **Permission**: "Consent of the academic unit and instructor"
- **Enrollment**: "Enrollment in MSCA Program"

#### 5. Corequisites
- Courses required concurrently (same semester)
- Format: "Corequisite: MATH1000"
- Common for lab/lecture pairings

### Key Observations
1. No nested prerequisite logic (no parentheses)
2. Grade requirements are uncommon but exist
3. Corequisites are explicitly labeled
4. Semicolon acts as higher-precedence AND separator
5. Course codes follow pattern: [A-Z]{4}[0-9]{4}

---

## Design Decisions (From Test Coverage Review)

### 1. Circular Dependency Handling

**Decision**: Store at parse time, detect and warn at validation time

**Reasoning**:
- Parser should be faithful to source data - if catalog has circular deps, parse as-is
- Validation service is the right place to detect cycles and return meaningful errors
- Allows tracking bad data in catalog without blocking parse/sync
- User-facing error: "Circular prerequisite detected: COMP1000 → COMP2000 → COMP1000"

**Implementation**:
- Parser creates CoursePrerequisite records even if circular
- Validator uses cycle detection algorithm (DFS/BFS) to identify loops
- API response includes `circular_dependency: true` flag when detected

### 2. Permission-Based Prerequisites

**Decision**: Store as special prerequisite type, display-only (no validation)

**Examples**: "Consent of instructor", "Consent of the academic unit"

**Implementation**:
```ruby
# Migration:
add_column :course_prerequisites, :special_requirement_text, :text
change_column_null :course_prerequisites, :prerequisite_course_id, true

# Enum expansion:
enum prerequisite_type: {
  standard: 0,
  corequisite: 1,
  permission: 2,        # NEW
  placement_test: 3     # NEW
}

# Model validations:
validates :prerequisite_course_id, presence: true, if: :standard_or_corequisite?
validates :special_requirement_text, presence: true, if: :special_requirement?

def standard_or_corequisite?
  standard? || corequisite?
end

def special_requirement?
  permission? || placement_test?
end
```

**Data integrity**:
- Standard/corequisite prerequisites MUST have `prerequisite_course_id` (references actual course)
- Permission/placement prerequisites MUST have `special_requirement_text` (no course reference)
- Validates at model level to prevent orphaned records

**Parser behavior**:
- Detect text matching `/consent|permission/i`
- Create `permission` type prerequisite with NULL `prerequisite_course_id`
- Store raw text in `special_requirement_text`

**Validator behavior**:
- Skip validation for `permission` type prerequisites
- Include in API response: `{ type: "permission", requirement: "Consent of instructor", validated: false }`
- UI displays: "⚠️ Additional requirement: Consent of instructor (contact department)"

### 3. Placement Test Prerequisites

**Decision**: Store as special type, display-only (future validation possible)

**Examples**: "MATH Placement", "MATH1000 or MATH Placement"

**Implementation**:
```ruby
# Same schema as permission prerequisites
# Parser detects /placement/i pattern
# Stores as placement_test type
```

**Validator behavior**:
- Skip programmatic validation (we don't have placement test scores in system)
- Include in response: `{ type: "placement", requirement: "MATH Placement", validated: false }`
- UI displays: "⚠️ May be satisfied by: MATH Placement exam (contact advising)"

**Future enhancement**: If placement test scores get added to User model, can implement validation later

### 4. Grade Boundary Cases

**Decision**: Use standardized grade comparison logic

**Edge cases**:
- B- grade: Does it satisfy "B or better"? **No** - only B, A-, A, A+ satisfy
- C+ grade: Does it satisfy "C or better"? **Yes** - C+ is higher than C
- Pass/Fail courses: Store as P/F, don't satisfy grade requirements (requires actual letter grade)

**Implementation**:
```ruby
# In PrerequisiteValidationService:
GRADE_VALUES = {
  "A+" => 13, "A" => 12, "A-" => 11,
  "B+" => 10, "B" => 9, "B-" => 8,
  "C+" => 7, "C" => 6, "C-" => 5,
  "D+" => 4, "D" => 3, "D-" => 2,
  "F" => 1
}

def meets_grade_requirement?(user_grade, required_grade)
  GRADE_VALUES[user_grade] >= GRADE_VALUES[required_grade]
end
```

---

## System Architecture

### Database Schema (Task #1 - Completed)

**CoursePrerequisite Model**
```ruby
# From Task #1:
class CoursePrerequisite < ApplicationRecord
  belongs_to :course
  belongs_to :prerequisite_course, class_name: 'Course'

  enum prerequisite_type: { standard: 0, corequisite: 1 }
  enum operator: { and: 0, or: 1 }

  # minimum_grade: string (A, B, C, D, or nil)
  # group_id: integer (for grouping OR clauses)
end
```

**Note**: The schema supports:
- Multiple prerequisites per course
- AND/OR logic via `operator` enum and `group_id`
- Grade requirements via `minimum_grade`
- Corequisites via `prerequisite_type` enum

### Service Layer Design

#### 1. CatalogScraperService

**Purpose**: Scrape course descriptions from catalog.wit.edu

**Key Methods**:
```ruby
class CatalogScraperService < ApplicationService
  def initialize(department_code)
    @department_code = department_code
  end

  def call
    # Scrape all courses for department
    # Returns array of {course_code:, title:, description:, prerequisite_text:}
  end

  private

  def fetch_page
    # HTTP request with error handling
  end

  def parse_courses(html)
    # Extract course blocks
  end

  def extract_prerequisite_text(course_node)
    # Find <em> tag containing "Prerequisite:" or "Corequisite:"
  end
end
```

**Error Handling**:
- HTTP errors (404, timeout, etc.) → log and raise
- HTML structure changes → Sentry alert (like DegreeAuditParserService)
- Invalid department codes → raise validation error

**Background Job**: `CatalogScraperJob.perform_later(department_code)`

#### 2. PrerequisiteParserService

**Purpose**: Parse prerequisite text into structured data for CoursePrerequisite records

**Key Methods**:
```ruby
class PrerequisiteParserService < ApplicationService
  def initialize(prerequisite_text, course:)
    @prerequisite_text = prerequisite_text
    @course = course
  end

  def call
    # Parse text and create/update CoursePrerequisite records
    # Returns array of CoursePrerequisite objects
  end

  private

  def extract_corequisites
    # Parse "Corequisite: MATH1000"
  end

  def extract_prerequisites
    # Parse prerequisite logic
  end

  def parse_logical_structure
    # Handle AND/OR logic with semicolons
    # Algorithm:
    # 1. Split by semicolons (high precedence AND groups)
    # 2. Within each group, split by " and " or ", "
    # 3. Within each AND clause, split by " or "
    # 4. Assign group_id for each OR clause
  end

  def extract_grade_requirement(text)
    # Regex: /completed with a grade of ([A-D])/
  end

  def extract_course_codes(text)
    # Regex: /[A-Z]{4}[0-9]{4}/
  end

  def find_or_create_prerequisite_course(course_code)
    # Look up Course by code or create placeholder
  end
end
```

**Parsing Algorithm**:

Example: "COMP1050; MATH2300 or MATH2800"

1. Split by semicolon → ["COMP1050", "MATH2300 or MATH2800"]
2. Group 1 (ID: 1):
   - COMP1050 (operator: and, group_id: 1)
3. Group 2 (ID: 2):
   - MATH2300 (operator: or, group_id: 2)
   - MATH2800 (operator: or, group_id: 2)

**Validation**: SQL: `(group_id=1 AND ...) AND (group_id=2 OR ...)`

#### 3. PrerequisiteValidationService

**Purpose**: Check if user has met prerequisites for a course

**Key Methods**:
```ruby
class PrerequisiteValidationService < ApplicationService
  def initialize(course:, user:)
    @course = course
    @user = user
  end

  def call
    # Check all prerequisites
    # Returns { eligible: true/false, unmet_prerequisites: [...], details: {...} }
  end

  private

  def user_completed_courses
    # Get user's completed courses with grades
    # From UserCourse model (Task #1)
  end

  def check_prerequisite(prerequisite)
    # Verify user has completed course with minimum grade
  end

  def check_prerequisite_group(group_id)
    # For OR groups: at least one must be met
    # For AND groups: all must be met
  end

  def check_corequisites
    # Verify concurrent enrollment in current term
  end
end
```

**Response Format**:
```json
{
  "eligible": false,
  "unmet_prerequisites": [
    {
      "course_code": "MATH2300",
      "minimum_grade": "C",
      "status": "not_taken"
    },
    {
      "course_code": "COMP1050",
      "minimum_grade": null,
      "status": "grade_too_low",
      "user_grade": "D"
    }
  ],
  "details": {
    "groups": [
      {"group_id": 1, "met": true},
      {"group_id": 2, "met": false}
    ]
  }
}
```

### API Layer

#### API::PrerequisitesController

**Endpoints**:

1. **GET /api/courses/:id/prerequisites**
   - Returns prerequisite tree for course
   - Response includes all prerequisites with AND/OR logic
   - Authorization: Any authenticated user

2. **POST /api/courses/:id/check_eligibility**
   - Checks if current user meets prerequisites
   - Returns eligibility status and unmet requirements
   - Authorization: User must own the check (checking own eligibility)

**Controller Design**:
```ruby
class Api::PrerequisitesController < Api::BaseController
  before_action :authenticate_user!
  before_action :set_course

  def index
    # GET /api/courses/:id/prerequisites
    prerequisites = @course.course_prerequisites
                           .includes(:prerequisite_course)
                           .order(:group_id, :operator)

    render json: PrerequisiteSerializer.new(prerequisites).serializable_hash
  end

  def check_eligibility
    # POST /api/courses/:id/check_eligibility
    authorize @course, :check_prerequisite?

    result = PrerequisiteValidationService.call(course: @course, user: current_user)

    render json: result
  end

  private

  def set_course
    @course = Course.find(params[:id])
  end
end
```

### Background Jobs

#### 1. CatalogScraperJob

**Purpose**: Periodically scrape all departments to keep prerequisites up-to-date

**Schedule**: Nightly (via cron or recurring job)

```ruby
class CatalogScraperJob < ApplicationJob
  queue_as :default

  def perform
    Department.pluck(:code).each do |dept_code|
      courses = CatalogScraperService.call(dept_code)

      courses.each do |course_data|
        course = Course.find_or_initialize_by(code: course_data[:course_code])
        course.update!(
          title: course_data[:title],
          description: course_data[:description]
        )

        if course_data[:prerequisite_text].present?
          PrerequisiteParserService.call(
            course_data[:prerequisite_text],
            course: course
          )
        end
      end
    end
  end
end
```

#### 2. PrerequisiteSyncJob (Optional)

**Purpose**: Re-parse prerequisites for a single course (for manual updates)

---

## Testing Strategy

**Total Estimated Coverage**: ~1,700 lines of test code (more complex than Task #2's 1,243 lines)

### Testing Workflow (Priority Order)

1. **Parser tests FIRST** - Core logic foundation
2. **Validator tests** - Depends on parser output
3. **Scraper tests** - Can develop in parallel
4. **API request specs** - Integration layer
5. **Integration tests** - Full flow validation

### Testing Priority Levels

**HIGH PRIORITY** (catches critical bugs):
- Circular dependency detection
- Grade boundary cases (B- vs "B or better")
- Transfer credits handling
- Admin authorization (all 4 access levels)
- Advisory locks for concurrent scraping

**MEDIUM PRIORITY** (edge cases):
- Permission/placement parsing
- Character encoding issues
- Self-referencing prerequisites
- N+1 query prevention

**LOW PRIORITY** (nice-to-have):
- Unicode character handling
- Multiple whitespace variations
- Performance optimization tests

---

### 1. Service Specs

#### **CatalogScraperService** (`spec/services/catalog_scraper_service_spec.rb`)

**Estimated: 200+ lines**

**Core Functionality**:
- ✅ Successful scraping with VCR cassettes
- ✅ HTTP error handling (404, 500, timeout)
- ✅ HTML structure changes (Sentry alerts)
- ✅ Invalid department codes
- ✅ Course extraction accuracy
- ✅ Prerequisite text extraction

**Additional Scenarios** (from test coverage review):
- **Rate limiting/politeness delays** - Verify delays between requests
- **Partial HTML extraction** - Some courses parse, others fail
- **Empty department** - Department code valid but has no courses
- **Redirect handling** - HTTP 301/302 responses
- **Character encoding issues** - Non-UTF8 characters in descriptions
- **Multiple prerequisite blocks** - Edge case: duplicate `<em>` tags per course
- **VCR cassette maintenance** - Instructions for updating cassettes

---

#### **PrerequisiteParserService** (`spec/services/prerequisite_parser_service_spec.rb`)

**Estimated: 400+ lines (most complex service)**

**Core Functionality**:
- ✅ Simple prerequisites (single course)
- ✅ AND logic (multiple courses)
- ✅ OR logic (alternative courses)
- ✅ Mixed AND/OR with semicolons
- ✅ Grade requirements parsing
- ✅ Corequisites parsing
- ✅ Invalid course codes (placeholder creation)
- ✅ Idempotency (re-parsing same text)

**Edge Cases**:
- ✅ Empty prerequisite text
- ✅ Malformed text
- ✅ Non-course prerequisites ("permission", "placement")

**Additional Scenarios** (from test coverage review):
- **Circular dependencies** - Course A requires B, B requires A (store, don't reject)
- **Self-referencing prerequisites** - Course requires itself (detect as invalid)
- **Case sensitivity** - "COMP1000" vs "comp1000" normalization
- **Whitespace variations** - Extra spaces, tabs, newlines
- **Orphaned course codes** - Prerequisites reference non-existent courses
- **Multiple grade requirements** - "MATH2100 with B and COMP1000 with C"
- **Nested logic edge case** - Unexpected parentheses (graceful handling)
- **Unicode/special characters** - Course codes with unusual characters
- **Group ID assignment consistency** - Same structure → same group_id pattern
- **Performance with complex prerequisites** - Course with 10+ groups
- **Permission-based prerequisites** - "Consent of instructor" → permission type
- **Placement test prerequisites** - "MATH Placement" → placement_test type

**Complex Test Case Example**:
```
"COMP1050; MATH2300 or MATH2800; PHYS2000 completed with a grade of B or better; Consent of instructor"
```
Expected output:
- Group 1: COMP1050 (AND)
- Group 2: MATH2300 OR MATH2800
- Group 3: PHYS2000 with grade B requirement
- Group 4: Permission type (special_requirement_text)

---

#### **PrerequisiteValidationService** (`spec/services/prerequisite_validation_service_spec.rb`)

**Estimated: 300+ lines**

**Core Functionality**:
- ✅ User meets all prerequisites
- ✅ User missing prerequisites
- ✅ User has insufficient grade
- ✅ OR group scenarios (one met, none met)
- ✅ AND group scenarios
- ✅ Corequisite validation

**Edge Cases**:
- ✅ No prerequisites
- ✅ User has no completed courses

**Additional Scenarios** (from test coverage review):
- **Transfer credits** - User completed equivalent course at another institution
- **Grade boundary cases** - User has B-, "B or better" required (not satisfied)
- **Grade boundary cases** - User has C+, "C or better" required (satisfied)
- **In-progress courses** - User currently enrolled, not yet completed
- **Withdrawn courses** - User withdrew with W grade (doesn't satisfy)
- **Course retakes** - User failed then passed, use highest grade
- **Multiple prerequisite paths** - OR group with 3+ options, user meets 2
- **Empty user course history** - Brand new student (no courses)
- **Concurrent corequisite validation** - Two courses are each other's corequisites
- **Partial group completion** - Which specific courses are missing?
- **Permission-based prerequisites** - Skip validation, include in response
- **Placement test prerequisites** - Skip validation, include in response
- **Circular dependency detection** - Detect cycle and return error
- **Self-referencing prerequisite** - Course requires itself (invalid)

**Grade Comparison Test Matrix**:
```
User Grade | Required Grade | Expected Result
-----------|---------------|----------------
A          | B or better   | ✅ Satisfied
B-         | B or better   | ❌ Not satisfied
C+         | C or better   | ✅ Satisfied
C          | C or better   | ✅ Satisfied
C-         | C or better   | ❌ Not satisfied
P (Pass)   | B or better   | ❌ Not satisfied (no letter grade)
```

---

### 2. Request Specs

#### **API::PrerequisitesController** (`spec/requests/api/prerequisites_spec.rb`)

**Estimated: 400+ lines (similar to Task #2 degree audit specs)**

**GET /api/courses/:id/prerequisites**:
- ✅ Valid course with prerequisites
- ✅ Course with no prerequisites
- ✅ Course not found (404)
- ✅ Authentication required
- ✅ Response format validation
- **Complex prerequisite tree** - Course with 5+ groups, verify JSON structure
- **Corequisites vs prerequisites** - Response differentiates types
- **Special prerequisites** - Permission/placement types in response
- **Pagination** - If prerequisite list is very long (unlikely)

**POST /api/courses/:id/check_eligibility**:
- ✅ User eligible
- ✅ User not eligible (unmet prerequisites)
- ✅ Authorization (users check own eligibility)
- ✅ Response includes unmet requirements details
- **Admin checking another user** - Should be allowed per authorization.md
- **Partially eligible** - User meets some groups but not all
- **User exceeds requirements** - User has A but only C required
- **Multiple unmet prerequisites** - Response lists ALL unmet
- **User has in-progress courses** - How does it affect eligibility?
- **Response performance** - Verify N+1 query prevention
- **Circular dependency response** - Returns circular_dependency flag
- **Special prerequisites in response** - Permission/placement with validated: false

**OpenAPI Documentation**:
- ✅ Tag with `:openapi` for automatic API docs generation
- ✅ Document request/response schemas
- ✅ Include example responses

**Response Format Example**:
```json
{
  "eligible": false,
  "unmet_prerequisites": [
    {
      "course_code": "MATH2300",
      "minimum_grade": "C",
      "status": "not_taken"
    }
  ],
  "special_requirements": [
    {
      "type": "permission",
      "requirement": "Consent of instructor",
      "validated": false
    }
  ],
  "circular_dependency": false,
  "details": {
    "groups": [
      {"group_id": 1, "met": true},
      {"group_id": 2, "met": false}
    ]
  }
}
```

---

### 3. Policy Specs

#### **CoursePolicy** (`spec/policies/course_policy_spec.rb`)

**Estimated: 60+ lines**

**check_prerequisite? Permission**:
- ✅ All authenticated users can check prerequisites
- **Test all 4 access levels** (user/admin/super_admin/owner) per authorization.md
- **Unauthenticated user** - Should be denied
- **Admin checking ANY user's eligibility** - Should be allowed
- **User checking another user's eligibility** - Should be denied (own resources only)

**Access Level Matrix**:
```
Action                          | user | admin | super_admin | owner
-------------------------------|------|-------|-------------|-------
View course prerequisites       |  ✅  |  ✅   |     ✅      |  ✅
Check own eligibility           |  ✅  |  ✅   |     ✅      |  ✅
Check another user's eligibility|  ❌  |  ✅   |     ✅      |  ✅
```

---

### 4. Job Specs

#### **CatalogScraperJob** (`spec/jobs/catalog_scraper_job_spec.rb`)

**Estimated: 150+ lines**

**Core Functionality**:
- ✅ Enqueues correctly
- ✅ Calls CatalogScraperService for each department
- ✅ Creates/updates courses
- ✅ Triggers PrerequisiteParserService

**Additional Scenarios** (from test coverage review):
- **Job failure handling** - One department fails, continue with others
- **Partial failure** - Some courses succeed, some fail
- **Idempotency** - Running job twice doesn't duplicate data
- **Monitoring/alerting** - Verify Sentry notifications on repeated failures
- **Job timeout** - What if scraping takes too long?
- **Database transaction handling** - Rollback on errors?
- **Performance with 20+ departments** - Job duration tracking
- **Advisory lock acquisition** - Prevent concurrent job execution

---

### 5. Integration Tests

#### **Full Prerequisite Flow** (`spec/integration/prerequisite_flow_spec.rb`)

**Estimated: 200+ lines**

**Core Flows**:
- ✅ Scrape → Parse → Validate end-to-end
- ✅ Verify CoursePrerequisite records created correctly
- ✅ Verify user eligibility checks work with real data

**Additional Scenarios** (from test coverage review):
- **Multi-course prerequisite chain** - A requires B requires C, user has C
- **User completes prerequisite then checks eligibility** - Cache invalidation
- **Prerequisite change detection** - Catalog updates, user's eligibility changes
- **Concurrent user checks** - Multiple users checking same course
- **Full semester registration flow** - User checks 4 courses, validates all
- **Transfer student scenario** - User has transfer credits, checks upper-level courses
- **Complex prerequisite tree traversal** - 5+ levels deep
- **Circular dependency handling** - Detection and error response

---

### Performance Testing

Add RSpec benchmark expectations:
```ruby
expect { parser_service.call }.to perform_under(100).ms
expect { validation_service.call }.to perform_under(200).ms
expect { api_endpoint }.to perform_under(500).ms
```

**Performance Targets**:
- Parser: Handle 50+ prerequisite courses in <100ms
- Validation: Check 10+ prerequisite groups in <200ms
- API endpoint: Respond in <500ms for complex prerequisites
- Background job: Process 1 department in <30 seconds

---

### Mock/Stub Strategy

1. **CatalogScraperService**:
   - Use **VCR cassettes** for real HTTP interactions
   - Mock HTTP errors (timeout, 404, 500) to avoid actual failures
   - Test against **frozen HTML fixtures** to detect structure changes

2. **PrerequisiteParserService**:
   - Use **real Course objects** from FactoryBot
   - Test prerequisite creation in **database** to verify associations
   - Mock Sentry for error notification tests

3. **PrerequisiteValidationService**:
   - Use **real UserCourse records** from FactoryBot
   - Build complete user course histories with factories
   - Don't mock validation logic (test actual algorithm)

4. **API Controllers**:
   - Use **real database records** via FactoryBot
   - Mock background jobs (don't actually enqueue during tests)
   - Use **request specs** (not controller specs) for full stack testing

---

### Critical Testing Notes

1. **VCR cassettes MUST be committed** - So CI can run without hitting catalog.wit.edu
2. **Test fixtures for all prerequisite patterns** - Don't rely only on live data
3. **Policy specs MUST test all 4 access levels** - Per authorization.md patterns
4. **Request specs MUST have :openapi tag** - For automatic API doc generation
5. **Advisory lock tests critical** - Prevent concurrent scraping
6. **Grade comparison tests exhaustive** - Cover all boundary cases (B-, C+, etc.)
7. **Circular dependency detection** - Use DFS/BFS algorithm, test thoroughly

---

## Implementation Plan (After PR #344 and #346 merge)

### Phase 1: Scraper (Week 1)
1. Create `CatalogScraperService`
2. Write service specs with VCR cassettes
3. Handle HTTP errors and structure changes
4. Create `CatalogScraperJob`
5. Write job specs

### Phase 2: Parser (Week 1-2)
1. Create `PrerequisiteParserService`
2. Implement logical structure parsing algorithm
3. Handle all prerequisite patterns (AND/OR/mixed)
4. Parse grade requirements and corequisites
5. Write comprehensive service specs (15+ scenarios)

### Phase 3: Validator (Week 2)
1. Create `PrerequisiteValidationService`
2. Implement group-based validation logic
3. Check user's completed courses and grades
4. Handle corequisites validation
5. Write service specs (10+ scenarios)

### Phase 4: API (Week 2)
1. Create `Api::PrerequisitesController`
2. Implement GET /api/courses/:id/prerequisites
3. Implement POST /api/courses/:id/check_eligibility
4. Add Pundit authorization
5. Write request specs with OpenAPI generation (10+ scenarios)

### Phase 5: Jobs & Scheduling (Week 2)
1. Set up recurring CatalogScraperJob (nightly)
2. Add monitoring for job failures
3. Test job execution

### Phase 6: Integration & Documentation (Week 2)
1. End-to-end integration tests
2. Update docs/prerequisite-system/README.md
3. Document API endpoints in API docs
4. Add prerequisite UI badge logic (frontend task)

---

## Implementation Decisions (Resolved)

1. **Circular Dependencies**: ✅ **RESOLVED**
   - Store at parse time, detect and warn at validation time
   - Validator uses cycle detection algorithm (DFS/BFS)
   - API response includes `circular_dependency: true` flag

2. **Permission-Based Prerequisites**: ✅ **RESOLVED**
   - Store as `permission` type with `special_requirement_text`
   - Skip validation, display to user with `validated: false`
   - UI shows: "⚠️ Additional requirement: Consent of instructor"

3. **Placement Test Prerequisites**: ✅ **RESOLVED**
   - Store as `placement_test` type with `special_requirement_text`
   - Skip validation (no placement scores in system)
   - Future enhancement: Add validation if scores added to User model

4. **Grade Boundary Cases**: ✅ **RESOLVED**
   - Use GRADE_VALUES hash with numeric comparison
   - B- does NOT satisfy "B or better" (only B, A-, A, A+)
   - C+ DOES satisfy "C or better"
   - Pass/Fail courses don't satisfy grade requirements

5. **Schema Changes**: ✅ **RESOLVED**
   - Add `special_requirement_text` text column
   - Expand `prerequisite_type` enum: standard/corequisite/permission/placement_test

---

## Open Questions (Still To Resolve)

1. **Department List**: How do we get the list of all department codes?
   - Option A: Hardcode based on WIT's departments
   - Option B: Scrape department list from catalog homepage
   - **Recommendation**: Start with hardcoded list, add scraping later

2. **Placeholder Courses**: When parsing prerequisites, should we create Course records for courses that don't exist in our database?
   - **Recommendation**: Yes, create placeholder records with `scraped: false` flag. Background job will fill in details later.

3. **Grade Data Source**: Where do we get user's grades for completed courses?
   - From `UserCourse` model (Task #1) - has `grade` field
   - Assumes grades are scraped from LeopardWeb

4. **Prerequisite Change Detection**: Should we track when prerequisites change?
   - **Recommendation**: Store `prerequisites_updated_at` on Course model
   - Alert users if prerequisites change for courses they're planning to take

5. **Corequisite Validation Timing**: When do we validate corequisites?
   - At registration time (checking if user is also enrolling in corequisite)
   - Requires access to user's planned courses for upcoming term
   - **Recommendation**: Implement after CRN generation (Task #5) is complete

6. **Transfer Credit Handling**: How to determine if transfer credit satisfies prerequisite?
   - Requires course equivalency data (not in current schema)
   - **Recommendation**: Phase 2 enhancement after MVP

---

## Performance Considerations

1. **Scraping Frequency**:
   - Prerequisites rarely change (maybe once per semester)
   - Nightly scraping is sufficient
   - Add manual trigger for emergency updates

2. **Validation Caching**:
   - Eligibility checks could be cached per user/course pair
   - Cache invalidation: when user's completed courses change
   - **Recommendation**: Implement caching if validation becomes slow

3. **Database Indexes**:
   - Index on `course_prerequisites.group_id` for efficient grouping
   - Index on `course_prerequisites.course_id` for prerequisite lookup
   - **Recommendation**: Add in migration

---

## Security Considerations

1. **Authorization**:
   - All users can view prerequisites (public data)
   - Users can only check their own eligibility (user-owned data)
   - Admins can check eligibility for any user (for support)

2. **Input Validation**:
   - Validate course IDs in API requests
   - Sanitize scraped HTML to prevent XSS
   - Validate department codes before scraping

3. **Rate Limiting**:
   - Scraping: Use delays between requests to avoid overloading catalog.wit.edu
   - API: Use Rack::Attack to prevent abuse of eligibility checks

4. **Data Privacy**:
   - User's completed courses and grades are sensitive
   - Only expose to authorized users (self or admin)
   - Don't include in API responses unless necessary

---

## Future Enhancements (Post-MVP)

1. **Prerequisite Recommendations**: Suggest course sequences to meet prerequisites
2. **Prerequisite Visualization**: Graph view of prerequisite chains
3. **Smart Registration Planning**: Automatically plan course sequences across semesters
4. **Prerequisite Waiver Tracking**: Track when users get prerequisite waivers
5. **Historical Prerequisites**: Track prerequisite changes over time
6. **Transfer Credit Integration**: Validate prerequisites against transfer credits

---

## References

- **Database Schema**: Task #1 (PR #344)
- **Existing Service Patterns**: `app/services/google_calendar_service.rb`, `app/services/degree_audit_parser_service.rb`
- **API Patterns**: `app/controllers/api/degree_audits_controller.rb`
- **Authorization Patterns**: `docs/authorization.md`
- **Testing Patterns**: `spec/services/degree_audit_parser_service_spec.rb`
- **Job Patterns**: `app/jobs/google_calendar_sync_job.rb`
