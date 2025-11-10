# Calendar Template Variables Reference

## Introduction

This document provides a comprehensive reference for all variables available in calendar event title and description templates. Templates use the [Liquid](https://shopify.github.io/liquid/) templating language.

## Basic Usage

Variables are inserted using double curly braces:

```liquid
{{variable_name}}
```

## Available Variables

### Course Information

#### `{{title}}`
Full course title from the course record.

**Example value:** `"Computer Science I"`

**Usage:**
```liquid
{{title}}
→ "Computer Science I"

{{title}} - Section {{section_number}}
→ "Computer Science I - Section 01"
```

---

#### `{{course_code}}`
Complete course code including subject, number, and section.

**Example value:** `"COMP-101-01"`

**Usage:**
```liquid
{{course_code}}: {{title}}
→ "COMP-101-01: Computer Science I"

[{{course_code}}] {{schedule_type}}
→ "[COMP-101-01] Lecture"
```

---

#### `{{subject}}`
Subject/department code.

**Example value:** `"COMP"`

**Usage:**
```liquid
{{subject}} {{course_number}}
→ "COMP 101"

{{subject}}-{{course_number}}
→ "COMP-101"
```

---

#### `{{course_number}}`
Course number (without subject or section).

**Example value:** `"101"`

**Usage:**
```liquid
{{subject}} {{course_number}}
→ "COMP 101"

Course {{course_number}}
→ "Course 101"
```

---

#### `{{section_number}}`
Section number for this course.

**Example value:** `"01"`

**Usage:**
```liquid
{{title}} (Section {{section_number}})
→ "Computer Science I (Section 01)"
```

---

#### `{{crn}}`
Course Reference Number - unique identifier for this course section.

**Example value:** `"12345"`

**Usage:**
```liquid
[CRN:{{crn}}] {{title}}
→ "[CRN:12345] Computer Science I"

{{course_code}} ({{crn}})
→ "COMP-101-01 (12345)"
```

---

### Location Information

#### `{{room}}`
Room number or name.

**Example value:** `"306"`

**Usage:**
```liquid
{{title}} - Room {{room}}
→ "Computer Science I - Room 306"

Rm. {{room}}
→ "Rm. 306"
```

---

#### `{{building}}`
Building name where the class meets.

**Example value:** `"Wentworth Hall"`

**Usage:**
```liquid
{{building}} {{room}}
→ "Wentworth Hall 306"

{{title}} @ {{building}}
→ "Computer Science I @ Wentworth Hall"
```

---

#### `{{location}}`
Pre-formatted full location string (building - room).

**Example value:** `"Wentworth Hall - 306"`

**Usage:**
```liquid
{{title}} in {{location}}
→ "Computer Science I in Wentworth Hall - 306"

{{location}}: {{course_code}}
→ "Wentworth Hall - 306: COMP-101-01"
```

---

### Faculty/Instructor Information

#### `{{faculty}}`
Primary faculty/instructor name.

**Example value:** `"Dr. Jane Smith"`

**Usage:**
```liquid
{{title}} - {{faculty}}
→ "Computer Science I - Dr. Jane Smith"

{{faculty}}'s {{subject}} Class
→ "Dr. Jane Smith's COMP Class"
```

---

#### `{{all_faculty}}`
Comma-separated list of all faculty teaching the course.

**Example value:** `"Dr. Jane Smith, Prof. John Doe"`

**Usage:**
```liquid
{{title}} with {{all_faculty}}
→ "Computer Science I with Dr. Jane Smith, Prof. John Doe"

Instructors: {{all_faculty}}
→ "Instructors: Dr. Jane Smith, Prof. John Doe"
```

---

### Time Information

#### `{{start_time}}`
Formatted meeting start time.

**Example value:** `"9:00 AM"`

**Usage:**
```liquid
{{start_time}} - {{title}}
→ "9:00 AM - Computer Science I"

Class at {{start_time}}
→ "Class at 9:00 AM"
```

---

#### `{{end_time}}`
Formatted meeting end time.

**Example value:** `"10:30 AM"`

**Usage:**
```liquid
{{title}} ({{start_time}}-{{end_time}})
→ "Computer Science I (9:00 AM-10:30 AM)"

Until {{end_time}}
→ "Until 10:30 AM"
```

---

#### `{{day}}`
Full day of week name.

**Example value:** `"Monday"`

**Usage:**
```liquid
{{day}}: {{title}}
→ "Monday: Computer Science I"

{{day}} {{schedule_type}}
→ "Monday Lecture"
```

---

#### `{{day_abbr}}`
Abbreviated day of week (3 letters).

**Example value:** `"Mon"`

**Usage:**
```liquid
{{day_abbr}} {{start_time}}
→ "Mon 9:00 AM"

[{{day_abbr}}] {{title}}
→ "[Mon] Computer Science I"
```

---

### Academic Information

#### `{{term}}`
Academic term name.

**Example value:** `"Spring 2024"`

**Usage:**
```liquid
{{title}} - {{term}}
→ "Computer Science I - Spring 2024"

{{term}}: {{course_code}}
→ "Spring 2024: COMP-101-01"
```

---

#### `{{schedule_type}}`
Type of scheduled meeting (lecture, laboratory, hybrid, etc.). The value is automatically capitalized.

**Example value:** `"Lecture"`, `"Laboratory"`, `"Hybrid"`

**Usage:**
```liquid
{{title}} ({{schedule_type}})
→ "Computer Science I (Lecture)"

{{schedule_type}}: {{title}}
→ "Lecture: Computer Science I"
```

---

#### `{{schedule_type_short}}`
Shorthand version of the schedule type. Specifically converts "Laboratory" to "Lab" while keeping other types as-is.

**Example value:** `"Lab"` (from Laboratory), `"Lecture"`, `"Hybrid"`

**Usage:**
```liquid
{{title}} - {{schedule_type_short}}
→ "Computer Science I - Lab"

{{schedule_type_short}}: {{course_code}}
→ "Lab: COMP-101-01"
```

---

## Liquid Filters

Liquid provides built-in filters to transform variables. Here are commonly useful ones:

### `capitalize`
Capitalizes the first letter of a string.

```liquid
{{schedule_type | capitalize}}
→ "Lecture" (from "lecture")
```

### `upcase`
Converts string to uppercase.

```liquid
{{subject | upcase}}
→ "COMP" (already uppercase in this case)

{{schedule_type | upcase}}
→ "LECTURE" (from "lecture")
```

### `downcase`
Converts string to lowercase.

```liquid
{{building | downcase}}
→ "wentworth hall" (from "Wentworth Hall")
```

### `truncate`
Shortens a string to specified length.

```liquid
{{title | truncate: 20}}
→ "Computer Science..." (from "Computer Science I")
```

### `replace`
Replaces occurrences of a string.

```liquid
{{location | replace: ' - ', ' in '}}
→ "Wentworth Hall in 306" (from "Wentworth Hall - 306")
```

### `remove`
Removes all occurrences of a string.

```liquid
{{course_code | remove: '-'}}
→ "COMP10101" (from "COMP-101-01")
```

### `split`
Splits a string into an array (useful with conditional logic).

```liquid
{% assign parts = course_code | split: '-' %}
{{parts[0]}}
→ "COMP"
```

## Conditional Logic

### If Statements

Show content only when a condition is true:

```liquid
{{title}}{% if faculty %} - {{faculty}}{% endif %}
→ "Computer Science I - Dr. Smith" (if faculty exists)
→ "Computer Science I" (if faculty is blank)
```

### If/Else

Choose between two options:

```liquid
{% if schedule_type == 'Laboratory' %}Lab{% else %}Class{% endif %}: {{title}}
→ "Lab: Computer Science I" (if laboratory)
→ "Class: Computer Science I" (otherwise)
```

### Multiple Conditions

```liquid
{% if schedule_type == 'Laboratory' %}
  Lab: {{title}} in {{room}}
{% elsif schedule_type == 'Hybrid' %}
  {{title}} [Hybrid]
{% else %}
  {{course_code}}: {{title}}
{% endif %}
```

### Case Statements

Better for multiple options:

```liquid
{% case schedule_type %}
  {% when 'Laboratory' %}
    🧪 Lab: {{title}}
  {% when 'Lecture' %}
    📚 Lecture: {{title}}
  {% when 'Hybrid' %}
    💻 {{title}} (Hybrid)
  {% else %}
    {{title}}
{% endcase %}
```

## Template Examples

### Minimal Templates

**Just the course code:**
```liquid
{{course_code}}
```
Result: `"COMP-101-01"`

**Subject and number only:**
```liquid
{{subject}} {{course_number}}
```
Result: `"COMP 101"`

**Title only:**
```liquid
{{title}}
```
Result: `"Computer Science I"`

---

### Informative Templates

**Course code with title:**
```liquid
{{course_code}}: {{title}}
```
Result: `"COMP-101-01: Computer Science I"`

**Day and time:**
```liquid
{{day_abbr}} {{start_time}}: {{title}}
```
Result: `"Mon 9:00 AM: Computer Science I"`

**Location focused:**
```liquid
{{title}} @ {{building}} {{room}}
```
Result: `"Computer Science I @ Wentworth Hall 306"`

---

### Schedule Type Specific

**Laboratory classes:**
```liquid
{{title}} - Lab ({{room}})
```
Result: `"Computer Science I - Lab (306)"`

**Lecture classes:**
```liquid
{{course_code}}: {{title}}
```
Result: `"COMP-101-01: Computer Science I"`

**Hybrid classes:**
```liquid
{{title}} [{{schedule_type | capitalize}}]
```
Result: `"Computer Science I [Hybrid]"`

---

### Detailed Templates

**Full information:**
```liquid
{{day_abbr}} {{start_time}}-{{end_time}}: {{title}} ({{room}})
```
Result: `"Mon 9:00 AM-10:30 AM: Computer Science I (306)"`

**With instructor:**
```liquid
{{course_code}} w/ {{faculty}}
```
Result: `"COMP-101-01 w/ Dr. Smith"`

**Complete description:**
```liquid
{{title}} - {{schedule_type | capitalize}}
{{day}} {{start_time}} - {{end_time}}
{{location}}
Instructor: {{faculty}}
```
Result:
```
Computer Science I - Lecture
Monday 9:00 AM - 10:30 AM
Wentworth Hall - 306
Instructor: Dr. Smith
```

---

### Creative Templates

**Emoji indicators:**
```liquid
{% case schedule_type %}
  {% when 'laboratory' %}🧪
  {% when 'lecture' %}📚
  {% when 'hybrid' %}💻
  {% else %}📖
{% endcase %} {{title}}
```
Result: `"📚 Computer Science I"`

**Compact format:**
```liquid
{{subject}}{{course_number}}.{{section_number}} {{day_abbr}}@{{start_time}}
```
Result: `"COMP101.01 Mon@9:00 AM"`

**Student-friendly:**
```liquid
{{title}} class in {{room}}
```
Result: `"Computer Science I class in 306"`

---

## Common Patterns

### Pattern: Show room for labs only

```liquid
{{title}}{% if schedule_type == 'Laboratory' %} - Lab ({{room}}){% endif %}
```

### Pattern: Include faculty if available

```liquid
{{course_code}}{% if faculty %} - {{faculty}}{% endif %}
```

### Pattern: Time-based format

```liquid
{{start_time}}: {{subject}} {{course_number}}
```

### Pattern: Different formats by day

```liquid
{% if day == 'Monday' or day == 'Wednesday' %}
  Lecture: {{title}}
{% else %}
  {{title}} - {{schedule_type}}
{% endif %}
```

### Pattern: CRN for registration tracking

```liquid
{{title}} [CRN: {{crn}}]
```

## Best Practices

1. **Keep it concise** - Calendar titles should be scannable at a glance
2. **Test your templates** - Use the preview endpoint to see results
3. **Handle missing data** - Use conditionals when optional fields might be blank
4. **Be consistent** - Use similar patterns across event types
5. **Consider mobile** - Shorter templates work better on small screens

## Validation Rules

Templates must follow these rules:

- **Valid Liquid syntax** - Malformed templates will be rejected
- **Whitelisted variables only** - Only documented variables are allowed
- **No unsafe filters** - Filters that could execute code are blocked
- **Reasonable length** - Maximum 500 characters for title templates
- **Safe characters** - Some special characters may be escaped for Google Calendar compatibility

## Testing Templates

Use the preview endpoint to test before saving:

```bash
curl -X POST /api/calendar_preferences/preview \
  -H "Content-Type: application/json" \
  -d '{
    "template": "{{day_abbr}} {{start_time}}: {{title}}",
    "meeting_time_id": 42
  }'
```

Response shows rendered output:
```json
{
  "rendered": "Mon 9:00 AM: Computer Science I",
  "valid": true
}
```

## Troubleshooting

### Template doesn't render

**Problem:** Variable shows as empty
**Solution:** Check if the data exists in the database (e.g., faculty might not be assigned)

**Problem:** Template shows literal `{{variable}}`
**Solution:** Invalid variable name - check spelling against this reference

**Problem:** Template causes an error
**Solution:** Check Liquid syntax, ensure all `{% %}` tags are properly closed

### Common Mistakes

❌ **Wrong:** `{title}` (single braces)
✅ **Correct:** `{{title}}` (double braces)

❌ **Wrong:** `{{ title}}` or `{{title }}` (spaces inside braces)
✅ **Correct:** `{{title}}` (no spaces)

❌ **Wrong:** `{{Title}}` (capital T)
✅ **Correct:** `{{title}}` (lowercase, exact match)

❌ **Wrong:** `{% if schedule_type == laboratory %}` (unquoted string)
✅ **Correct:** `{% if schedule_type == 'laboratory' %}` (quoted string)

## Support

For questions or issues with templates:
1. Check this reference for variable names and syntax
2. Test using the preview endpoint
3. Review example templates in this document
4. Check the main [Calendar Preferences documentation](./calendar_preferences.md)
