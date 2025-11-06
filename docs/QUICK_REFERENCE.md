# Calendar Preferences - Quick Reference

## 🚀 Quick Start

### For Extension Developers
1. Read: [`extension_integration_guide.md`](./calendar-preferences/extension_integration_guide.md)
2. API Reference: [`api_calendar_preferences.md`](./calendar-preferences/api_calendar_preferences.md)
3. Template Variables: [`template_variables.md`](./calendar-preferences/template_variables.md)

### For Backend Developers
1. Architecture: [`calendar_preferences.md`](./calendar-preferences/calendar_preferences.md)
2. Implementation: [`../CALENDAR_PREFERENCES_IMPLEMENTATION.md`](needs-sort/CALENDAR_PREFERENCES_IMPLEMENTATION.md)

## 📋 API Endpoints Cheat Sheet

| Method | Endpoint | Purpose |
|--------|----------|---------|
| `GET` | `/api/calendar_preferences` | List all user's preferences |
| `GET` | `/api/calendar_preferences/:id` | Get global or event-type pref |
| `PUT` | `/api/calendar_preferences/:id` | Update preference |
| `DELETE` | `/api/calendar_preferences/:id` | Delete event-type pref |
| `POST` | `/api/calendar_preferences/preview` | Preview template |
| `GET` | `/api/meeting_times/:id/preference` | Get event pref + resolution |
| `PUT` | `/api/meeting_times/:id/preference` | Override individual event |
| `DELETE` | `/api/meeting_times/:id/preference` | Remove override |

## 🎯 Template Variables

### Most Common
```liquid
{{title}}           → "Computer Science I"
{{course_code}}     → "COMP-101-01"
{{room}}            → "306"
{{start_time}}      → "9:00 AM"
{{day_abbr}}        → "Mon"
```

### All Variables (17 total)
```
Course: title, course_code, subject, course_number, section_number, crn
Location: room, building, location
Faculty: faculty, all_faculty
Time: start_time, end_time, day, day_abbr
Academic: term, schedule_type
```

Full reference: [`template_variables.md`](./calendar-preferences/template_variables.md)

## 📝 Template Examples

### Basic
```liquid
{{course_code}}: {{title}}
→ "COMP-101-01: Computer Science I"
```

### With Time
```liquid
{{day_abbr}} {{start_time}}: {{title}}
→ "Mon 9:00 AM: Computer Science I"
```

### With Conditional
```liquid
{{title}}{% if room %} - Room {{room}}{% endif %}
→ "Computer Science I - Room 306"
```

### Labs
```liquid
{{title}} - Lab ({{room}})
→ "Computer Science I - Lab (306)"
```

## ⚙️ Preference Hierarchy

```
Individual Event Override  (highest priority)
    ↓
Event Type Preference (lecture, lab, hybrid)
    ↓
Global User Preference
    ↓
System Defaults  (lowest priority)
```

## 🎨 Color IDs

| ID | Color Name | ID | Color Name |
|----|------------|----|------------|
| 1  | Lavender   | 7  | Peacock    |
| 2  | Sage       | 8  | Graphite   |
| 3  | Grape      | 9  | Blueberry  |
| 4  | Flamingo   | 10 | Basil      |
| 5  | Banana     | 11 | Tomato     |
| 6  | Tangerine  |    |            |

## 🔔 Reminder Format

```json
{
  "reminder_settings": [
    {"minutes": 15, "method": "popup"},
    {"minutes": 1440, "method": "email"}
  ]
}
```

**Common Times:**
- 15 min = 15
- 30 min = 30
- 1 hour = 60
- 1 day = 1440
- 1 week = 10080

## 🔐 Authentication

All endpoints require JWT token:
```
Authorization: Bearer <your_jwt_token>
```

## 🐛 Common Errors

### Template Errors
```json
{
  "errors": ["Title template invalid syntax: unexpected token"]
}
```
**Fix:** Check template syntax, use preview endpoint

### Validation Errors
```json
{
  "errors": ["Color id must be between 1 and 11"]
}
```
**Fix:** Use valid values (check constraints)

## 💡 Quick Examples

### Set Global Default
```bash
curl -X PUT /api/calendar_preferences/global \
  -H "Authorization: Bearer TOKEN" \
  -d '{"calendar_preference": {"title_template": "{{course_code}}: {{title}}"}}'
```

### Override Wednesday Class
```bash
curl -X PUT /api/meeting_times/42/preference \
  -H "Authorization: Bearer TOKEN" \
  -d '{"event_preference": {"reminder_settings": [{"minutes": 60, "method": "popup"}]}}'
```

### Preview Template
```bash
curl -X POST /api/calendar_preferences/preview \
  -H "Authorization: Bearer TOKEN" \
  -d '{"template": "{{day}}: {{title}}", "meeting_time_id": 42}'
```

## 📖 Documentation Map

```
docs/
├── README.md                                           # Start here
├── QUICK_REFERENCE.md                                  # This file
└── calendar-preferences/
    ├── calendar_preferences.md                         # System architecture
    ├── api_calendar_preferences.md                     # API reference
    ├── template_variables.md                           # Template guide
    └── extension_integration_guide.md                  # Extension guide
```

## 🧪 Testing

```bash
# Run all preference tests
bundle exec rspec spec/models/calendar_preference_spec.rb
bundle exec rspec spec/services/calendar_template_renderer_spec.rb
bundle exec rspec spec/services/preference_resolver_spec.rb

# Test specific feature
bundle exec rspec spec/models/calendar_preference_spec.rb:42
```

## 🚨 Important Notes

1. **Templates are validated** - Invalid syntax will be rejected
2. **Only whitelisted variables** - Custom variables won't work
3. **Hierarchy matters** - Individual > EventType > Global > System
4. **Partial overrides** - Only set fields you want to change
5. **Trigger sync** - Changes apply on next calendar sync

## 📞 Need Help?

1. Check the full documentation in `/docs/`
2. Review test files for examples
3. Use preview endpoint to test templates
4. Open an issue on GitHub

---

**Quick Links:**
- [Full API Docs](./calendar-preferences/api_calendar_preferences.md)
- [Extension Guide](./calendar-preferences/extension_integration_guide.md)
- [Template Variables](./calendar-preferences/template_variables.md)
- [Implementation Summary](needs-sort/CALENDAR_PREFERENCES_IMPLEMENTATION.md)
