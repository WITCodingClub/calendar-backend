# Chrome Extension Integration Guide

## Quick Start

This guide helps Chrome extension developers integrate calendar preference management.

## Overview

The backend provides a complete calendar preferences API. The extension's job is to:
1. Provide a UI for users to configure preferences
2. Make API calls to save/retrieve preferences
3. Trigger calendar re-sync when preferences change

## Prerequisites

- JWT token for authenticated API requests
- User's meeting time data (to show relevant events)
- Access to calendar sync trigger mechanism

## Integration Steps

### Step 1: Add Preferences UI to Extension

Create UI sections for:
- **Global Preferences** - Default settings for all events
- **Event Type Preferences** - Settings per type (lecture, laboratory, hybrid)
- **Individual Event Overrides** - Per-event customization

### Step 2: Fetch Current Preferences

On extension load or when user opens preferences:

```javascript
async function loadPreferences(token) {
  const response = await fetch('https://your-api.com/api/calendar_preferences', {
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json'
    }
  });

  const data = await response.json();

  return {
    global: data.global,           // Global defaults
    eventTypes: data.event_types   // lecture, laboratory, hybrid
  };
}
```

### Step 3: Display in UI

```javascript
function displayPreferences(prefs) {
  // Global section
  document.getElementById('global-title-template').value =
    prefs.global?.title_template || '';

  // Event type sections
  document.getElementById('lecture-title-template').value =
    prefs.eventTypes.lecture?.title_template || '';
  document.getElementById('laboratory-title-template').value =
    prefs.eventTypes.laboratory?.title_template || '';

  // Show where settings are inherited from
  showInheritanceInfo(prefs);
}
```

### Step 4: Implement Live Preview

```javascript
// Debounce preview calls
const debouncedPreview = debounce(async (template, meetingTimeId, token) => {
  const response = await fetch('https://your-api.com/api/calendar_preferences/preview', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      template: template,
      meeting_time_id: meetingTimeId
    })
  });

  const data = await response.json();

  if (data.valid) {
    document.getElementById('preview').textContent = data.rendered;
    hideError();
  } else {
    showError(data.error);
  }
}, 300);

// Call on input
document.getElementById('title-template').addEventListener('input', (e) => {
  debouncedPreview(e.target.value, firstMeetingTimeId, token);
});
```

### Step 5: Save Preferences

```javascript
async function saveGlobalPreferences(token, preferences) {
  const response = await fetch('https://your-api.com/api/calendar_preferences/global', {
    method: 'PUT',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      calendar_preference: {
        title_template: preferences.titleTemplate,
        description_template: preferences.descriptionTemplate,
        reminder_settings: preferences.reminders,
        color_id: preferences.colorId,
        visibility: preferences.visibility
      }
    })
  });

  if (!response.ok) {
    const errors = await response.json();
    throw new Error(errors.errors.join(', '));
  }

  return await response.json();
}

async function saveEventTypePreferences(token, eventType, preferences) {
  const response = await fetch(`https://your-api.com/api/calendar_preferences/${eventType}`, {
    method: 'PUT',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      calendar_preference: preferences
    })
  });

  if (!response.ok) {
    const errors = await response.json();
    throw new Error(errors.errors.join(', '));
  }

  return await response.json();
}
```

### Step 6: Handle Individual Event Overrides

```javascript
async function getEventPreference(token, meetingTimeId) {
  const response = await fetch(
    `https://your-api.com/api/meeting_times/${meetingTimeId}/preference`,
    {
      headers: {
        'Authorization': `Bearer ${token}`
      }
    }
  );

  const data = await response.json();

  return {
    individual: data.individual_preference,  // User's overrides
    resolved: data.resolved,                  // What will actually be used
    sources: data.sources,                    // Where each setting comes from
    preview: data.preview                     // Rendered title
  };
}

async function saveEventOverride(token, meetingTimeId, overrides) {
  const response = await fetch(
    `https://your-api.com/api/meeting_times/${meetingTimeId}/preference`,
    {
      method: 'PUT',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        event_preference: overrides
      })
    }
  );

  return await response.json();
}
```

### Step 7: Trigger Calendar Sync

After saving any preferences:

```javascript
async function saveAndSync(token, preferences) {
  // 1. Save preferences
  await saveGlobalPreferences(token, preferences);

  // 2. Trigger calendar re-sync
  await fetch('https://your-api.com/api/user/gcal', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json'
    }
  });

  // 3. Show success message
  showSuccessMessage('Preferences saved! Calendar is updating...');
}
```

## UI Components to Build

### 1. Template Editor

```html
<div class="template-editor">
  <label>Title Template</label>
  <input type="text"
         id="title-template"
         placeholder="{{course_code}}: {{title}}"
         autocomplete="off">

  <div id="preview-box" class="preview">
    <strong>Preview:</strong>
    <span id="preview">COMP-101-01: Computer Science I</span>
  </div>

  <div id="error-box" class="error" style="display: none;">
    <span id="error-message"></span>
  </div>

  <details>
    <summary>Available Variables</summary>
    <ul>
      <li><code>{{title}}</code> - Course title</li>
      <li><code>{{course_code}}</code> - Full course code</li>
      <li><code>{{room}}</code> - Room number</li>
      <li><code>{{start_time}}</code> - Start time</li>
      <li><code>{{day_abbr}}</code> - Day abbreviation</li>
      <!-- etc -->
    </ul>
  </details>
</div>
```

### 2. Reminder Settings

```html
<div class="reminder-settings">
  <label>Reminders</label>
  <div id="reminder-list">
    <div class="reminder-item">
      <input type="number" value="15" min="0"> minutes before
      <select>
        <option value="popup">Popup</option>
        <option value="email">Email</option>
      </select>
      <button class="remove">×</button>
    </div>
  </div>
  <button id="add-reminder">+ Add Reminder</button>
</div>
```

### 3. Color Picker

```html
<div class="color-picker">
  <label>Color</label>
  <div class="color-grid">
    <div class="color-option" data-color-id="1" style="background: #a4bdfc;"></div>
    <div class="color-option" data-color-id="2" style="background: #7ae7bf;"></div>
    <div class="color-option" data-color-id="3" style="background: #dbadff;"></div>
    <!-- etc for all 11 colors -->
  </div>
</div>
```

### 4. Event Type Tabs

```html
<div class="preferences-tabs">
  <button class="tab active" data-scope="global">Global Default</button>
  <button class="tab" data-scope="lecture">Lectures</button>
  <button class="tab" data-scope="laboratory">Labs</button>
  <button class="tab" data-scope="hybrid">Hybrid</button>
</div>

<div class="preferences-content">
  <!-- Content changes based on active tab -->
</div>
```

### 5. Individual Event List

```html
<div class="event-list">
  <h3>Your Classes</h3>
  <div class="event-item">
    <div class="event-info">
      <strong>COMP-101-01</strong>
      <span>Mon/Wed 9:00 AM</span>
    </div>
    <div class="event-preview">
      <span class="preview-text">COMP-101-01: Computer Science I</span>
      <span class="inheritance-badge">Using global default</span>
    </div>
    <button class="customize-btn" data-meeting-id="42">Customize</button>
  </div>
  <!-- More events -->
</div>
```

## Example Complete Component

```javascript
class PreferenceManager {
  constructor(apiBaseUrl, token) {
    this.api = apiBaseUrl;
    this.token = token;
    this.cache = {};
  }

  async loadAll() {
    const response = await fetch(`${this.api}/calendar_preferences`, {
      headers: { 'Authorization': `Bearer ${this.token}` }
    });
    this.cache.preferences = await response.json();
    return this.cache.preferences;
  }

  async preview(template, meetingTimeId) {
    const response = await fetch(`${this.api}/calendar_preferences/preview`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${this.token}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ template, meeting_time_id: meetingTimeId })
    });
    return await response.json();
  }

  async saveGlobal(preferences) {
    return await this.save('global', preferences);
  }

  async saveEventType(eventType, preferences) {
    return await this.save(eventType, preferences);
  }

  async save(scope, preferences) {
    const response = await fetch(`${this.api}/calendar_preferences/${scope}`, {
      method: 'PUT',
      headers: {
        'Authorization': `Bearer ${this.token}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ calendar_preference: preferences })
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.errors.join(', '));
    }

    return await response.json();
  }

  async getEventPreference(meetingTimeId) {
    const response = await fetch(
      `${this.api}/meeting_times/${meetingTimeId}/preference`,
      { headers: { 'Authorization': `Bearer ${this.token}` } }
    );
    return await response.json();
  }

  async saveEventPreference(meetingTimeId, overrides) {
    const response = await fetch(
      `${this.api}/meeting_times/${meetingTimeId}/preference`,
      {
        method: 'PUT',
        headers: {
          'Authorization': `Bearer ${this.token}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ event_preference: overrides })
      }
    );
    return await response.json();
  }

  async deleteEventPreference(meetingTimeId) {
    await fetch(
      `${this.api}/meeting_times/${meetingTimeId}/preference`,
      {
        method: 'DELETE',
        headers: { 'Authorization': `Bearer ${this.token}` }
      }
    );
  }
}

// Usage
const prefs = new PreferenceManager('https://api.example.com/api', userToken);

// Load and display
const current = await prefs.loadAll();
displayInUI(current);

// Preview template
const preview = await prefs.preview('{{day_abbr}} {{start_time}}: {{title}}', 42);
console.log(preview.rendered); // "Mon 9:00 AM: Computer Science I"

// Save global
await prefs.saveGlobal({
  title_template: '{{course_code}}: {{title}}',
  reminder_settings: [{ minutes: 15, method: 'popup' }]
});

// Save event type
await prefs.saveEventType('laboratory', {
  title_template: '{{title}} - Lab ({{room}})',
  color_id: 7
});

// Override individual event
await prefs.saveEventPreference(42, {
  reminder_settings: [{ minutes: 60, method: 'popup' }]
});
```

## Template Variable Autocomplete

Provide autocomplete for template variables:

```javascript
const TEMPLATE_VARIABLES = [
  { name: '{{title}}', description: 'Course title', example: 'Computer Science I' },
  { name: '{{course_code}}', description: 'Full course code', example: 'COMP-101-01' },
  { name: '{{subject}}', description: 'Subject code', example: 'COMP' },
  { name: '{{course_number}}', description: 'Course number', example: '101' },
  { name: '{{section_number}}', description: 'Section', example: '01' },
  { name: '{{crn}}', description: 'Course Reference Number', example: '12345' },
  { name: '{{room}}', description: 'Room number', example: '306' },
  { name: '{{building}}', description: 'Building name', example: 'Wentworth Hall' },
  { name: '{{location}}', description: 'Full location', example: 'Wentworth Hall - 306' },
  { name: '{{faculty}}', description: 'Primary instructor', example: 'Dr. Jane Smith' },
  { name: '{{all_faculty}}', description: 'All instructors', example: 'Dr. Smith, Prof. Jones' },
  { name: '{{start_time}}', description: 'Start time', example: '9:00 AM' },
  { name: '{{end_time}}', description: 'End time', example: '10:30 AM' },
  { name: '{{day}}', description: 'Full day name', example: 'Monday' },
  { name: '{{day_abbr}}', description: 'Abbreviated day', example: 'Mon' },
  { name: '{{term}}', description: 'Academic term', example: 'Spring 2024' },
  { name: '{{schedule_type}}', description: 'Event type', example: 'lecture' }
];

function setupAutocomplete(inputElement) {
  // Implement autocomplete UI showing TEMPLATE_VARIABLES
  // Trigger on {{ or when user types
}
```

## Common Template Examples

Provide these as quick-start templates in the UI:

```javascript
const TEMPLATE_PRESETS = [
  {
    name: 'Course Code + Title',
    template: '{{course_code}}: {{title}}',
    example: 'COMP-101-01: Computer Science I'
  },
  {
    name: 'Day + Time + Title',
    template: '{{day_abbr}} {{start_time}}: {{title}}',
    example: 'Mon 9:00 AM: Computer Science I'
  },
  {
    name: 'Title + Room',
    template: '{{title}} ({{room}})',
    example: 'Computer Science I (306)'
  },
  {
    name: 'Minimal (Subject + Number)',
    template: '{{subject}} {{course_number}}',
    example: 'COMP 101'
  },
  {
    name: 'With Instructor',
    template: '{{course_code}} - {{faculty}}',
    example: 'COMP-101-01 - Dr. Smith'
  }
];
```

## Error Handling Checklist

✅ **Validate template syntax** - Use preview endpoint before saving
✅ **Handle network errors** - Show friendly messages if API is down
✅ **Display validation errors** - Show which field has an issue
✅ **Confirm before overriding** - Warn when creating individual overrides
✅ **Handle token expiration** - Refresh JWT or redirect to login
✅ **Show save progress** - Loading states during API calls

## Testing Checklist

✅ **Test template preview** - Verify live preview works
✅ **Test global save** - Save and verify preferences persist
✅ **Test event type save** - Save per-type preferences
✅ **Test individual override** - Override specific event
✅ **Test deletion** - Delete overrides and verify fallback
✅ **Test validation errors** - Submit invalid data, verify error display
✅ **Test with no preferences** - Verify defaults work
✅ **Test hierarchy** - Verify inheritance works correctly

## Performance Tips

1. **Debounce preview calls** - Don't hammer the API on every keystroke
2. **Cache preferences** - Store in extension storage, reload only when needed
3. **Batch operations** - If possible, save multiple changes at once
4. **Show loading states** - Use spinners/skeleton screens during API calls
5. **Optimize re-renders** - Only update UI elements that changed

## Security Considerations

- Always include JWT token in Authorization header
- Never store raw passwords in extension storage
- Sanitize user input before displaying (XSS prevention)
- Validate API responses before using data
- Use HTTPS for all API calls
