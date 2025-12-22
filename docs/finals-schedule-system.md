# Finals Schedule Management System

## Overview

The Finals Schedule system allows admins to upload PDF schedules of final exams, parse them automatically, and sync finals to user calendars.

## Data Models

### FinalExam
- `course_id` - Reference to Course
- `term_id` - Reference to Term
- `exam_date` - Date of the final exam
- `start_time` - Start time (integer HHMM format, e.g., 800 = 8:00 AM)
- `end_time` - End time (integer HHMM format)
- `location` - Exam location (building + room)
- `notes` - Special instructions
- `combined_crns` - JSON array of CRNs that share this exam slot (for display purposes)

**Unique constraint**: One final exam per course per term

**Helper Methods**:
- `formatted_start_time` / `formatted_end_time` - Returns "HH:MM" format
- `formatted_start_time_ampm` / `formatted_end_time_ampm` - Returns "H:MM AM/PM" format
- `duration_hours` - Returns exam duration as decimal hours
- `time_of_day` - Returns "morning", "afternoon", or "evening"
- `course_code` - Returns "SUBJ-COURSE-SECTION" format
- `primary_instructor` / `all_instructors` - Returns instructor names
- `start_datetime` / `end_datetime` - Returns full DateTime objects
- `combined_crns_display` - Returns comma-separated CRN list

### FinalsSchedule (Upload Tracking)
- `term_id` - Which term this schedule is for
- `uploaded_by_id` - Admin who uploaded it
- `status` - Processing status (pending/processing/completed/failed)
- `processed_at` - When parsing completed
- `error_message` - Any errors during parsing
- `stats` - JSONB field with parsing statistics (created, updated, skipped counts)
- `pdf_file` - ActiveStorage attachment

## Implementation Status

### Phase 1: Core Models ✅
- [x] Create FinalExam model with validations
- [x] Add associations to Course and Term
- [x] Add helper methods for time formatting
- [x] Add combined_crns field for multi-section finals

### Phase 2: PDF Parser Service ✅
- [x] Install `pdf-reader` gem (via Gemfile)
- [x] Create `FinalsScheduleParserService`
  - Uses `pdftotext` (poppler-utils) for PDF extraction
  - Secure command execution via `Open3.capture3`
  - Extracts CRNs, dates, times, locations
  - Matches CRNs to courses in database
  - Creates/updates FinalExam records
- [x] Handle multiple date/time formats
- [x] Add comprehensive error handling and logging

### Phase 3: Admin Interface ✅
- [x] Create FinalsSchedule model for tracking uploads
- [x] Add ActiveStorage for PDF uploads
- [x] Create admin controller (`Admin::FinalsSchedulesController`)
- [x] Create Pundit policy (`FinalsSchedulePolicy`)
  - index/show: admin+ access
  - create/destroy: super_admin+ access
- [x] Build upload form view with term selection
- [x] Display upload history and status
- [x] Show parsing results (created/updated/errors)
- [x] Add comparison view when replacing existing schedule
- [x] Limit term selection to current and future terms

### Phase 4: Background Processing ✅
- [x] Create `FinalsScheduleProcessJob`
  - Processes uploaded PDF in background
  - Updates status as processing completes
  - Queue: `:default`
  - Concurrency limited per schedule
- [x] Queue job after upload

### Phase 5: Calendar Integration ✅
- [x] Add `final_exam_id` to `google_calendar_events` table
- [x] Update `GoogleCalendarEvent` model with:
  - `belongs_to :final_exam, optional: true`
  - Scopes: `finals_only`, `courses_only`, `for_final_exam`
  - Helper methods: `final_exam?`, `meeting_time?`, `syncable`
- [x] Update `CourseScheduleSyncable` concern:
  - `build_finals_events_for_sync` - builds final exam events
  - `sync_final_exam` - syncs individual final exam
  - Finals included automatically in `sync_course_schedule`
- [x] Update `GoogleCalendarService`:
  - Handle both `meeting_time_id` and `final_exam_id`
  - Index events by composite key for proper tracking
  - Create events with `final_exam_id` when applicable
- [x] Style finals differently (red color, "Final Exam:" prefix)
- [x] Set more aggressive reminders for finals (1 day, 1 hour, 15 min)

### Phase 6: Template System ✅
- [x] Add finals-specific template variables:
  - `exam_date`, `exam_date_short` - Full and short date formats
  - `exam_time_of_day` - Morning/Afternoon/Evening
  - `duration` - Exam duration in hours
  - `event_type` - "class" or "final_exam"
  - `is_final_exam` - Boolean for conditional templates
  - `combined_crns` - All CRNs sharing this exam
- [x] Create `build_context_from_final_exam` method
- [x] Default title template: "Final Exam: {{title}}"
- [x] Default description: "{{course_code}}\n{{faculty}}\n{{location}}"
- [x] Event type preference support: `event_type: "final_exam"`

### Phase 7: User Preferences (Future)
- [ ] Add setting to hide/show finals on calendar
- [ ] Add custom reminder options for finals
- [ ] Allow users to override final exam times if incorrect

## PDF Parsing Strategy

### Expected PDF Format (WIT)
```
CRN    Course          Date          Time              Location
12345  COMP 1000-01   12/16/2025    8:00 AM-10:00 AM  WENTW 010
12346  MATH 2300-02   12/17/2025    1:00 PM-3:00 PM   AUD
```

### Parsing Approach
1. Extract text from PDF using `pdftotext -layout` (via Open3 for security)
2. Find lines with CRN patterns (5-digit numbers)
3. Extract date using regex (multiple formats: MM/DD/YYYY, Month DD YYYY, Mon DD YYYY)
4. Extract time range and convert to HHMM format (supports 12-hour and military)
5. Extract location (building + room pattern or special values like ONLINE/TBA)
6. Match CRN to existing courses in term
7. Create/update FinalExam records
8. Return statistics for admin display

### Error Handling
- Skip courses not found in database
- Log all parsing errors
- Track success/failure statistics
- Display detailed error report to admin

## Admin Workflow

1. **Upload PDF**
   - Admin navigates to `/admin/finals_schedules`
   - Selects term (current or future only) and uploads PDF
   - If term already has finals, shows comparison/confirmation view
   - System queues background job

2. **Processing**
   - Job parses PDF
   - Creates/updates FinalExam records
   - Updates FinalsSchedule status

3. **Review Results**
   - Admin sees parsing summary (created/updated/skipped/errors)
   - Reviews any errors or skipped courses
   - Can view all final exams for the term

4. **Calendar Sync**
   - Finals automatically included in next sync
   - Users see finals appear on their calendars with distinct styling

## Template Variables

### For Final Exams
| Variable | Description | Example |
|----------|-------------|---------|
| `title` | Course title | "Introduction to Programming" |
| `course_code` | Full course code | "COMP-1000-01" |
| `subject` | Subject code | "COMP" |
| `course_number` | Course number | "1000" |
| `section_number` | Section number | "01" |
| `crn` | Course reference number | "12345" |
| `location` | Exam location | "WENTW 010" |
| `faculty` | Primary instructor | "John Smith" |
| `all_faculty` | All instructors | "John Smith, Jane Doe" |
| `start_time` | Exam start time | "8:00 AM" |
| `end_time` | Exam end time | "10:00 AM" |
| `day` | Day of week | "Monday" |
| `day_abbr` | Day abbreviation | "Mon" |
| `term` | Term name | "Fall 2025" |
| `exam_date` | Full date | "December 16, 2025" |
| `exam_date_short` | Short date | "12/16/2025" |
| `exam_time_of_day` | Time category | "Morning" |
| `duration` | Exam duration | "2.0 hours" |
| `event_type` | Event type | "final_exam" |
| `is_final_exam` | Boolean flag | true |
| `combined_crns` | All related CRNs | "12345, 12346" |

## Default Preferences for Finals

```ruby
FINAL_EXAM_DEFAULTS = {
  title_template: "Final Exam: {{title}}",
  description_template: "{{course_code}}\n{{faculty}}\n{{location}}",
  location_template: "{{location}}",
  reminder_settings: [
    { "time" => "1", "type" => "days", "method" => "popup" },
    { "time" => "1", "type" => "hours", "method" => "popup" },
    { "time" => "15", "type" => "minutes", "method" => "popup" }
  ],
  color_id: 11,  # Tomato red
  visibility: "default"
}
```

## Files Created/Modified

### New Files
- `app/policies/finals_schedule_policy.rb`
- `app/jobs/finals_schedule_process_job.rb`
- `app/controllers/admin/finals_schedules_controller.rb`
- `app/views/admin/finals_schedules/index.html.erb`
- `app/views/admin/finals_schedules/new.html.erb`
- `app/views/admin/finals_schedules/show.html.erb`
- `app/views/admin/finals_schedules/confirm_replace.html.erb`
- `app/views/admin/finals_schedules/_status_badge.html.erb`
- `db/migrate/*_add_final_exam_id_to_google_calendar_events.rb`
- `db/migrate/*_add_foreign_key_for_final_exam_to_google_calendar_events.rb`
- `db/migrate/*_validate_foreign_key_for_final_exam_on_google_calendar_events.rb`
- `db/migrate/*_add_combined_crns_to_final_exams.rb`

### Modified Files
- `app/services/finals_schedule_parser_service.rb` - Security fix with Open3
- `app/models/finals_schedule.rb` - Updated to use pdf_content
- `app/models/final_exam.rb` - Added helpers, combined_crns serialization
- `app/models/term.rb` - Added `current_and_future` scope
- `app/models/google_calendar_event.rb` - Added final_exam association
- `app/models/concerns/course_schedule_syncable.rb` - Added finals sync
- `app/services/google_calendar_service.rb` - Handle finals in sync
- `app/services/calendar_template_renderer.rb` - Finals context builder
- `app/services/preference_resolver.rb` - Finals defaults
- `app/views/shared/_admin_navigation.html.erb` - Added Finals link
- `config/routes.rb` - Added admin routes

## Security Considerations

- Only admins (super_admin/owner) can upload finals schedules
- PDF file size and type validated
- Secure command execution via Open3 (no shell injection)
- All uploads tracked with user attribution
- Pundit authorization on all actions

## Known Limitations

1. **Regular classes during finals week**: Currently, regular class meetings continue to show during finals week. Future enhancement could detect finals week and adjust course recurrence end dates.

2. **Combined CRNs**: While `combined_crns` tracks related sections, each course still gets its own FinalExam record. This is by design to maintain the unique course-term constraint.

3. **PDF format dependency**: The parser is tuned for WIT's PDF format. Different formats may require parser adjustments.

## Testing Checklist

- [ ] FinalExam model validations and helpers
- [ ] FinalsSchedule model and status transitions
- [ ] FinalsScheduleParserService with sample PDFs
- [ ] FinalsScheduleProcessJob background processing
- [ ] FinalsSchedulePolicy authorization
- [ ] Admin controller CRUD operations
- [ ] Calendar sync includes finals
- [ ] Template rendering for finals
- [ ] Preference resolution for finals
