# OAuth Credential Management API

## Overview

This document describes the API endpoints for managing Google OAuth credentials and calendar access. These endpoints allow users to:

1. **List connected Google accounts** - View all OAuth connections
2. **Disconnect OAuth credentials** - Completely remove an OAuth connection
3. **Add email to calendar** - Share the calendar with an additional email
4. **Remove email from calendar** - Unshare the calendar from an email (without disconnecting OAuth)

## Important Distinctions

### OAuth Credential vs Calendar Access

Understanding the difference between these operations is critical:

- **OAuth Credential**: A complete Google OAuth connection that stores encrypted access/refresh tokens. Required to interact with Google Calendar API.
- **Calendar Access**: Permission for a specific email to view the shared calendar.

### Remove Email vs Disconnect Credential

**Remove Email from Calendar** (`DELETE /api/user/gcal/remove_email`):
- Removes calendar sharing (ACL rule) for that email
- OAuth connection **remains active**
- User can still re-add the email to calendar later
- Keeps encrypted tokens
- Use when: User wants to stop seeing calendar on one email but keep OAuth connection

**Disconnect OAuth Credential** (`DELETE /api/user/oauth_credentials/:credential_id`):
- **Completely removes** the OAuth connection
- Revokes calendar access for that email
- Deletes encrypted access/refresh tokens
- Associated GoogleCalendar record is destroyed
- Cannot be undone (user must re-authenticate)
- Use when: User wants to fully disconnect a Google account

## API Endpoints

### List Connected Google Accounts

Get all OAuth credentials connected to the current user's account.

**Endpoint**: `GET /api/user/oauth_credentials`

**Authentication**: Required (JWT Bearer token)

**Request Headers**:
```
Authorization: Bearer <jwt_token>
```

**Response** (`200 OK`):
```json
{
  "oauth_credentials": [
    {
      "id": 1,
      "email": "personal@gmail.com",
      "provider": "google",
      "has_calendar": true,
      "calendar_id": "abc123@group.calendar.google.com",
      "created_at": "2025-01-01T00:00:00.000Z"
    },
    {
      "id": 2,
      "email": "work@example.com",
      "provider": "google",
      "has_calendar": true,
      "calendar_id": "abc123@group.calendar.google.com",
      "created_at": "2025-01-02T00:00:00.000Z"
    }
  ]
}
```

**Response Fields**:
- `id`: OAuth credential ID (use this for disconnect endpoint)
- `email`: Email address for this OAuth connection
- `provider`: OAuth provider (currently always "google")
- `has_calendar`: Whether this credential has an associated GoogleCalendar record
- `calendar_id`: Google Calendar ID if calendar exists, otherwise `null`
- `created_at`: ISO 8601 timestamp of when credential was created

**Error Responses**:
- `401 Unauthorized`: Invalid or missing JWT token
- `403 Forbidden`: Beta access not enabled

**Example (JavaScript)**:
```javascript
const response = await fetch('/api/user/oauth_credentials', {
  headers: {
    'Authorization': `Bearer ${jwt}`
  }
});

const { oauth_credentials } = await response.json();

oauth_credentials.forEach(cred => {
  console.log(`${cred.email}: ${cred.has_calendar ? 'Connected' : 'No calendar'}`);
});
```

---

### Disconnect OAuth Credential

Completely remove a Google OAuth connection and revoke calendar access.

**Endpoint**: `DELETE /api/user/oauth_credentials/:credential_id`

**Authentication**: Required (JWT Bearer token)

**URL Parameters**:
- `credential_id` (required): OAuth credential ID from list endpoint

**Request Headers**:
```
Authorization: Bearer <jwt_token>
```

**Response** (`200 OK`):
```json
{
  "message": "OAuth credential disconnected successfully"
}
```

**Error Responses**:

`400 Bad Request` - Missing credential_id:
```json
{
  "error": "credential_id is required"
}
```

`404 Not Found` - Credential doesn't exist or belongs to another user:
```json
{
  "error": "OAuth credential not found"
}
```

`422 Unprocessable Entity` - Attempting to delete last credential:
```json
{
  "error": "Cannot disconnect the last OAuth credential. You must have at least one connected account."
}
```

`401 Unauthorized` - Invalid or missing JWT token

**Side Effects**:
1. OAuth credential record is deleted
2. Associated GoogleCalendar record is deleted (via `dependent: :destroy`)
3. Calendar access (ACL rule) is revoked for that email
4. If this was the primary credential, user may need to re-authenticate

**Example (JavaScript)**:
```javascript
// First, get the credential ID
const { oauth_credentials } = await fetch('/api/user/oauth_credentials', {
  headers: { 'Authorization': `Bearer ${jwt}` }
}).then(r => r.json());

const credentialToRemove = oauth_credentials.find(
  cred => cred.email === 'old@gmail.com'
);

// Then disconnect it
if (credentialToRemove) {
  const response = await fetch(
    `/api/user/oauth_credentials/${credentialToRemove.id}`,
    {
      method: 'DELETE',
      headers: { 'Authorization': `Bearer ${jwt}` }
    }
  );

  if (response.ok) {
    console.log('Successfully disconnected!');
  }
}
```

**Example (cURL)**:
```bash
# List credentials
curl -X GET https://api.example.com/api/user/oauth_credentials \
  -H "Authorization: Bearer YOUR_JWT"

# Disconnect credential ID 123
curl -X DELETE https://api.example.com/api/user/oauth_credentials/123 \
  -H "Authorization: Bearer YOUR_JWT"
```

---

### Add Email to Google Calendar

Share the WIT Courses calendar with an additional email address. If the email doesn't have OAuth credentials yet, this returns an OAuth URL. If it does, the calendar is immediately shared.

**Endpoint**: `POST /api/user/gcal/add_email`

**Authentication**: Required (JWT Bearer token)

**Request Headers**:
```
Authorization: Bearer <jwt_token>
Content-Type: application/json
```

**Request Body**:
```json
{
  "email": "another@gmail.com"
}
```

**Response** (`200 OK`) - Calendar shared successfully:
```json
{
  "message": "Calendar shared with email",
  "calendar_id": "abc123@group.calendar.google.com"
}
```

**Error Responses**:

`400 Bad Request` - Missing email:
```json
{
  "error": "Email is required"
}
```

`422 Unprocessable Entity` - No OAuth credentials exist yet:
```json
{
  "error": "You must complete Google OAuth for at least one email before adding calendar access. Please use the /api/user/gcal endpoint first."
}
```

**Side Effects**:
1. Creates/updates `Email` record with `g_cal = true`
2. Shares calendar with email (ACL rule)
3. Adds calendar to that email's Google Calendar list (if OAuth credentials exist)

**Notes**:
- If the email already has OAuth credentials, the calendar is immediately shared
- If the email doesn't have OAuth credentials, complete OAuth flow first via `/api/user/gcal`
- The calendar must already exist (created during first OAuth flow)

**Example (JavaScript)**:
```javascript
const response = await fetch('/api/user/gcal/add_email', {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${jwt}`,
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({ email: 'work@example.com' })
});

const data = await response.json();
console.log(`Calendar ${data.calendar_id} shared with work@example.com`);
```

---

### Remove Email from Google Calendar

Remove calendar sharing for a specific email without disconnecting the OAuth credential.

**Endpoint**: `DELETE /api/user/gcal/remove_email`

**Authentication**: Required (JWT Bearer token)

**Request Headers**:
```
Authorization: Bearer <jwt_token>
Content-Type: application/json
```

**Request Body**:
```json
{
  "email": "old@gmail.com"
}
```

**Response** (`200 OK`):
```json
{
  "message": "Email removed from Google Calendar association"
}
```

**Error Responses**:

`400 Bad Request` - Missing email:
```json
{
  "error": "Email is required"
}
```

`404 Not Found` - Email not found or not associated with calendar:
```json
{
  "error": "Email not found or not associated with Google Calendar"
}
```

`404 Not Found` - No calendar exists:
```json
{
  "error": "No Google Calendar found to remove access from"
}
```

**Side Effects**:
1. Updates `Email` record: `g_cal = false`
2. Removes calendar sharing (ACL rule) for that email
3. Email stops seeing the calendar in Google Calendar
4. **OAuth credentials remain intact** - user can re-add later

**Notes**:
- This does NOT delete the OAuth credential
- User can re-add the email to calendar later without re-authenticating
- To completely disconnect, use `DELETE /api/user/oauth_credentials/:credential_id` instead

**Example (JavaScript)**:
```javascript
const response = await fetch('/api/user/gcal/remove_email', {
  method: 'DELETE',
  headers: {
    'Authorization': `Bearer ${jwt}`,
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({ email: 'old@gmail.com' })
});

if (response.ok) {
  console.log('Calendar access removed for old@gmail.com');
}
```

---

## Common Workflows

### View All Connected Accounts

```javascript
const { oauth_credentials } = await fetch('/api/user/oauth_credentials', {
  headers: { 'Authorization': `Bearer ${jwt}` }
}).then(r => r.json());

console.log('Connected accounts:');
oauth_credentials.forEach(cred => {
  console.log(`- ${cred.email} (ID: ${cred.id})`);
});
```

### Disconnect a Specific Account

```javascript
// 1. Get credential ID
const { oauth_credentials } = await fetch('/api/user/oauth_credentials', {
  headers: { 'Authorization': `Bearer ${jwt}` }
}).then(r => r.json());

const cred = oauth_credentials.find(c => c.email === 'old@gmail.com');

// 2. Disconnect
if (cred) {
  await fetch(`/api/user/oauth_credentials/${cred.id}`, {
    method: 'DELETE',
    headers: { 'Authorization': `Bearer ${jwt}` }
  });
}
```

### Share Calendar with New Email (Without OAuth)

If you want to share the calendar with an email that doesn't need OAuth access:

```javascript
await fetch('/api/user/gcal/add_email', {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${jwt}`,
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({ email: 'shared@example.com' })
});
```

**Note**: This requires at least one OAuth credential to already exist.

---

## Security & Authorization

All endpoints use:
- **Pundit authorization**: Ensures users can only manage their own credentials
- **JWT authentication**: All requests require valid JWT Bearer token
- **Beta access check**: V1 feature flag must be enabled
- **Encrypted tokens**: OAuth access/refresh tokens are encrypted with Lockbox

### Authorization Rules

From `OauthCredentialPolicy`:
- Users can view, create, update, and delete **their own** credentials
- Admins can view all credentials (read-only for support)
- Super admins can modify any credentials
- Users must keep at least one OAuth credential (cannot delete last one)

---

## Rate Limiting

All API endpoints are protected by Rack::Attack rate limiting:
- **Per-user limits**: 100 requests per minute per JWT
- **Global limits**: 1000 requests per minute total
- Exceeding limits returns `429 Too Many Requests`

See [Rate Limiting docs](../security/rate-limiting.md) for details.

---

## Related Documentation

- **[Multi-Email OAuth Flow](./multi-email-google-calendar-oauth.md)** - Complete OAuth flow documentation
- **[Authorization](../authorization.md)** - Pundit policies and access control
- **[Rate Limiting](../security/rate-limiting.md)** - API rate limits and protection

---

## Testing

### RSpec Tests

Full test coverage available in `spec/requests/api/oauth_credentials_spec.rb`.

**Key test scenarios**:
- ✅ List credentials (empty, single, multiple)
- ✅ Disconnect credential (success, last credential prevention, not found)
- ✅ Authorization (can't delete other users' credentials)
- ✅ Calendar cleanup (GoogleCalendar record deleted on disconnect)

### Manual Testing

```bash
# 1. List credentials
curl -X GET http://localhost:3000/api/user/oauth_credentials \
  -H "Authorization: Bearer YOUR_JWT"

# 2. Disconnect credential
curl -X DELETE http://localhost:3000/api/user/oauth_credentials/123 \
  -H "Authorization: Bearer YOUR_JWT"

# 3. Add email to calendar
curl -X POST http://localhost:3000/api/user/gcal/add_email \
  -H "Authorization: Bearer YOUR_JWT" \
  -H "Content-Type: application/json" \
  -d '{"email": "new@gmail.com"}'

# 4. Remove email from calendar
curl -X DELETE http://localhost:3000/api/user/gcal/remove_email \
  -H "Authorization: Bearer YOUR_JWT" \
  -H "Content-Type: application/json" \
  -d '{"email": "old@gmail.com"}'
```

---

## Troubleshooting

### "Cannot disconnect the last OAuth credential"

**Cause**: User is trying to delete their only OAuth credential.

**Solution**: Connect another account first, then disconnect the unwanted one.

### "OAuth credential not found"

**Causes**:
1. Credential ID is invalid
2. Credential belongs to another user
3. Credential was already deleted

**Solution**: Use `GET /api/user/oauth_credentials` to get valid credential IDs.

### "No Google Calendar found to remove access from"

**Cause**: User has no GoogleCalendar record (calendar was never created).

**Solution**: Complete OAuth flow via `/api/user/gcal` first.

### Calendar still appears after removal

**Cause**: Calendar access removal (ACL) can take a few minutes to propagate.

**Solution**: Wait 2-5 minutes and refresh Google Calendar.

---

## Migration Path

This API supersedes the manual admin-only revocation that was previously available only at `/admin/users/:id/oauth_credentials/:credential_id` (admin panel).

Users can now self-manage their OAuth credentials through the API, reducing support burden and improving user experience.
