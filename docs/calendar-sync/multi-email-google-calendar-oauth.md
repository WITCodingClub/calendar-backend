# Multi-Email Google Calendar OAuth Flow

## Overview

This document describes the OAuth flow for connecting multiple email addresses to a user's Google Calendar. This flow is designed for Chrome extension usage, minimizing server requests and providing clear success/failure feedback.

## Architecture

### Database Schema

- **`oauth_credentials` table**: Stores OAuth tokens for each email
  - `user_id`: Foreign key to users table
  - `provider`: OAuth provider (currently only "google")
  - `email`: Email address for this OAuth connection
  - `access_token`: Encrypted OAuth access token
  - `refresh_token`: Encrypted OAuth refresh token
  - `token_expires_at`: Token expiration timestamp
  - `uid`: Provider's unique identifier
  - `metadata`: JSONB for additional data (e.g., `course_calendar_id`)

- **Unique Index**: `(user_id, provider, email)` - Allows multiple Google OAuth connections per user

### Key Services

1. **`GoogleOauthStateService`**: Generates and verifies signed JWT state parameters
2. **`GoogleCalendarService`**: Handles calendar creation, sharing, and OAuth-based calendar list management

## User Flow (Chrome Extension)

### Step 1: Request OAuth URL

Extension calls `/api/user/gcal` with a single email:

```bash
POST /api/user/gcal
Content-Type: application/json

{
  "email": "jaspermayone@gmail.com"
}
```

**Response** (when OAuth needed):
```json
{
  "message": "OAuth required",
  "email": "jaspermayone@gmail.com",
  "oauth_url": "/auth/google_oauth2?state=eyJhbG..."
}
```

**Response** (when email already OAuth'd):
```json
{
  "message": "Email already connected",
  "calendar_id": "74a23fc8e0d20b751e83183c614e284429a0e2376b5d9cc080d4a38da1989e9a@group.calendar.google.com"
}
```

### Step 2: Open OAuth URL

Extension opens the OAuth URL (e.g., in a popup or new tab). User completes Google OAuth for the email.

### Step 3: OAuth Callback Processing

After user authorizes, Google redirects to `/auth/google_oauth2/callback?state=...&code=...`

**Backend automatically**:
1. Verifies the signed state parameter
2. Extracts `user_id` and `email` from state
3. Verifies OAuth email matches expected email
4. Creates/updates `OauthCredential` for that email
5. Creates calendar (if doesn't exist)
6. Shares calendar with the email
7. Adds calendar to that email's Google Calendar list
8. Redirects to `/oauth/success?email=...&calendar_id=...`

### Step 4: Extension Detects Success/Failure

**Success page** (`/oauth/success`):
- Meta tags: `<meta name="oauth-status" content="success">`
- Posts message to `window.opener` with OAuth result
- Auto-closes after 3 seconds

**Failure page** (`/oauth/failure`):
- Meta tags: `<meta name="oauth-status" content="failure">`
- Displays error message
- Posts error to `window.opener`

Extension can detect success by:
- Listening for `postMessage` events
- Monitoring popup URL changes
- Reading meta tags from the page

## Security

### State Parameter

The state parameter is a signed JWT containing:
```json
{
  "user_id": 123,
  "email": "user@example.com",
  "nonce": "random-hex-string",
  "exp": 1699999999
}
```

- **Signed** with `Rails.application.secret_key_base`
- **Expires** in 1 hour
- **Verified** in callback to prevent tampering
- Ensures OAuth email matches the intended email

### Email Validation

During callback:
1. Verify state JWT signature and expiration
2. Extract expected email from state
3. Verify `auth.info.email` matches expected email
4. Reject if mismatch

## Backend Implementation Details

### Models

**`OauthCredential`**:
```ruby
validates :email, presence: true
validates :provider, presence: true
validates :uid, uniqueness: { scope: :provider }

# Unique index on (user_id, provider, email)
```

**`User` (via `GoogleOauthable` concern)**:
```ruby
def google_credentials
  oauth_credentials.where(provider: "google")
end

def google_credential_for_email(email)
  oauth_credentials.find_by(provider: "google", email: email)
end
```

### Controllers

**`Api::UsersController#request_g_cal`**:
1. Parse email from request
2. Create/update `Email` record with `g_cal = true`
3. Generate OAuth URL if email doesn't have credentials
4. Return OAuth URL to extension (or calendar_id if already connected)

**`AuthController#google`** (callback):
- If `params[:state]` present → calendar OAuth flow
- Otherwise → admin login flow

**`AuthController#handle_calendar_oauth`**:
1. Verify state parameter
2. Create OAuth credential for specific email
3. Create/share calendar
4. Redirect to success page

### Google Calendar Service

**`GoogleCalendarService#create_or_get_course_calendar`**:
1. Create calendar if doesn't exist (using service account)
2. Share calendar with all `g_cal = true` emails
3. Add calendar to each OAuth'd email's Google Calendar list

**Calendar Sharing**:
```ruby
# Share with email (ACL rule)
service.insert_acl(calendar_id, {
  scope: { type: 'user', value: email },
  role: 'reader'
})
```

**Calendar List Addition**:
```ruby
# Add to user's calendar list (requires OAuth)
service.insert_calendar_list({
  id: calendar_id,
  summary_override: "WIT Courses",
  color_id: "5",
  selected: true,
  hidden: false
})
```

## Extension Integration Example

```javascript
// 1. Request OAuth URL
const response = await fetch('/api/user/gcal', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${jwt}`
  },
  body: JSON.stringify({ email: 'jaspermayone@gmail.com' })
});

const data = await response.json();

// 2. Open OAuth URL if needed
if (data.oauth_url) {
  const popup = window.open(
    `https://your-domain.com${data.oauth_url}`,
    `oauth_${data.email}`,
    'width=600,height=700'
  );

  // 3. Listen for success/failure
  window.addEventListener('message', (event) => {
    if (event.data.type === 'oauth-success') {
      console.log('Success!', event.data.email, event.data.calendarId);
    } else if (event.data.type === 'oauth-failure') {
      console.error('Failed:', event.data.error);
    }
  });
} else {
  console.log('Email already connected!', data.calendar_id);
}
```

## Testing

### Manual Testing

1. **Create test user**:
   ```ruby
   user = User.create!
   user.emails.create!(email: 'test@example.com', primary: true)
   ```

2. **Request OAuth URL**:
   ```bash
   curl -X POST http://localhost:3000/api/user/gcal \
     -H "Authorization: Bearer YOUR_JWT" \
     -H "Content-Type: application/json" \
     -d '{"email": "your-email@gmail.com"}'
   ```

3. **Open OAuth URL** in browser and complete flow

4. **Verify** calendar appears in Google Calendar

### RSpec Tests

Test coverage should include:
- `GoogleOauthStateService` JWT generation and verification
- `Api::UsersController#request_g_cal` OAuth URL generation
- `AuthController#handle_calendar_oauth` credential creation
- `GoogleCalendarService` calendar sharing and list addition

## Troubleshooting

### "Invalid or expired state parameter"
- State JWT expired (>1 hour old)
- State JWT tampered with
- Check Rails secret_key_base

### "OAuth email does not match expected email"
- User authorized different email than expected
- Ask user to sign in with correct Google account

### "User has no Google credential"
- OAuth flow hasn't completed yet
- Credential wasn't saved properly
- Check `oauth_credentials` table

### Calendar not appearing in Google Calendar
- Check ACL rules were created (share step)
- Check calendar was added to user's list (requires OAuth)
- Verify user has OAuth credentials for that email

## Future Enhancements

1. **Webhook notifications**: Notify extension when OAuth completes (vs. polling)
2. **Batch OAuth**: Single OAuth flow for multiple emails (if Google supports)
3. **Email verification**: Verify email ownership before allowing OAuth
4. **Revocation**: Allow users to revoke individual email connections
