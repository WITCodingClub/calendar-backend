# Google Cross-Account Protection (RISC)

This document explains the Google Cross-Account Protection (RISC - Risk and Incident Sharing and Coordination) implementation in the Calendar Backend.

## Overview

Cross-Account Protection is a security feature from Google that sends real-time security event notifications to your application when important security events occur on users' Google accounts. This allows you to take proactive security measures to protect your users.

## What is RISC?

RISC (based on the OpenID Foundation standard) allows Google to notify your application about:

- **Account compromises** (hijacking attempts)
- **Session revocations** (user signed out of all sessions)
- **OAuth token revocations** (user revoked app access)
- **Account disabling** (Google disabled the account)
- **Account enabling** (Google re-enabled the account)
- **Credential changes** (user changed password/2FA)

## How It Works

1. Google sends an HTTPS POST request to your RISC webhook endpoint (`/risc/events`)
2. The POST body contains a cryptographically signed JWT (JSON Web Token)
3. Your application validates the JWT signature using Google's public keys
4. Your application processes the event and takes appropriate action
5. Your application returns HTTP 202 (Accepted) to acknowledge receipt

## Architecture

```
Google RISC Service
      |
      | POST /risc/events
      | (JWT token)
      v
RiscController
      |
      | Enqueue background job
      v
ProcessRiscEventJob
      |
      v
RiscValidationService ----> Validate JWT
      |                     Decode payload
      |                     Extract event data
      v
RiscEventHandlerService --> Handle event
      |                     Take security action
      |                     Create SecurityEvent record
      v
SecurityEvent (database)
```

## Components

### 1. RiscController
- **Location**: `app/controllers/risc_controller.rb`
- **Purpose**: Webhook endpoint that receives security event tokens from Google
- **Key Features**:
  - Public endpoint (no authentication required)
  - CSRF protection disabled
  - Immediately enqueues background job
  - Returns HTTP 202 Accepted

### 2. ProcessRiscEventJob
- **Location**: `app/jobs/process_risc_event_job.rb`
- **Purpose**: Background job that processes security events asynchronously
- **Queue**: `high` (priority queue)
- **Retry Logic**: Exponential backoff, 3 attempts
- **Key Features**:
  - Validates and decodes JWT token
  - Checks for duplicate events (using `jti`)
  - Delegates to RiscEventHandlerService

### 3. RiscValidationService
- **Location**: `app/services/risc_validation_service.rb`
- **Purpose**: Validates and decodes security event tokens
- **Key Features**:
  - Fetches Google's RISC configuration
  - Fetches Google's public signing keys
  - Validates JWT signature
  - Verifies issuer and audience
  - Caches configuration and keys (1 hour TTL)

### 4. RiscEventHandlerService
- **Location**: `app/services/risc_event_handler_service.rb`
- **Purpose**: Handles security events and takes appropriate actions
- **Key Features**:
  - Finds affected user by Google subject ID
  - Creates SecurityEvent record
  - Takes security actions based on event type
  - Handles verification events

### 5. SecurityEvent Model
- **Location**: `app/models/security_event.rb`
- **Purpose**: Stores security event data
- **Key Features**:
  - Links to User and OauthCredential
  - Encrypts raw event data (Lockbox)
  - Tracks processing status
  - 90-day retention policy
  - Scopes for filtering

### 6. SecurityEventPolicy
- **Location**: `app/policies/security_event_policy.rb`
- **Purpose**: Authorization policy for security events
- **Access Control**:
  - Users can view their own events
  - Admins can view all events (for monitoring)
  - Super admins can delete events
  - No one can create/update manually

## Event Types and Response Actions

### 1. Sessions Revoked
**Event Type**: `https://schemas.openid.net/secevent/risc/event-type/sessions-revoked`

**When It Occurs**: Google has revoked all active sessions for the user

**Our Response**:
- Revoke all Google OAuth credentials
- Unshare calendar access

**Reason**: User requested session revocation or security policy

### 2. Tokens Revoked
**Event Type**: `https://schemas.openid.net/secevent/oauth/event-type/tokens-revoked`

**When It Occurs**: Google has revoked all OAuth tokens for the user

**Our Response**:
- Revoke all Google OAuth credentials
- Delete refresh tokens
- Unshare calendar access

**Reason**: User revoked app access

### 3. Token Revoked (Single)
**Event Type**: `https://schemas.openid.net/secevent/oauth/event-type/token-revoked`

**When It Occurs**: Google has revoked a specific OAuth token

**Our Response**:
- Revoke all Google OAuth credentials (safer approach since tokens are encrypted)

**Reason**: Token-specific revocation

### 4. Account Disabled
**Event Type**: `https://schemas.openid.net/secevent/risc/event-type/account-disabled`

**When It Occurs**: Google has disabled the user's account

**Our Response**:
- If reason is "hijacking": **Immediately revoke all OAuth credentials**
- Otherwise: Log for monitoring

**Reason**: "hijacking" (compromised), "bulk-account" (suspicious activity), or unspecified

### 5. Account Enabled
**Event Type**: `https://schemas.openid.net/secevent/risc/event-type/account-enabled`

**When It Occurs**: Google has re-enabled the user's account

**Our Response**:
- Log the event
- User can re-authenticate normally

**Reason**: Account restored after review

### 6. Credential Change Required
**Event Type**: `https://schemas.openid.net/secevent/risc/event-type/account-credential-change-required`

**When It Occurs**: Google recommends the user change their credentials

**Our Response**:
- Log for monitoring
- Watch for suspicious activity

**Reason**: Potential security concern

### 7. Verification
**Event Type**: `https://schemas.openid.net/secevent/risc/event-type/verification`

**When It Occurs**: Test event to verify webhook is working

**Our Response**:
- Log the verification
- Mark as processed

**Reason**: Testing/verification

## Setup Instructions

### Prerequisites

1. **Google Cloud Project** with OAuth configured
2. **Service Account** with RISC Configuration Admin role
3. **Public HTTPS endpoint** for receiving webhooks
4. **OAuth Client IDs** configured

### Step 1: Enable RISC API

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select your project
3. Navigate to **APIs & Services** > **Library**
4. Search for "RISC API"
5. Click **Enable**
6. Review and accept the RISC Terms of Service

### Step 2: Create Service Account

1. Go to **APIs & Services** > **Credentials**
2. Click **Create Credentials** > **Service account**
3. Give it a name (e.g., "RISC Service Account")
4. Assign the role: **RISC Configuration Admin** (`roles/riscconfigs.admin`)
5. Create and download the JSON key
6. Save the key to `config/service_account_key.json` (or set `GOOGLE_SERVICE_ACCOUNT_KEY_PATH`)

### Step 3: Configure OAuth Client IDs

Set your Google OAuth client IDs in one of two ways:

**Option 1: Environment Variable**
```bash
export GOOGLE_OAUTH_CLIENT_IDS="your-client-id-1.apps.googleusercontent.com,your-client-id-2.apps.googleusercontent.com"
```

**Option 2: Rails Credentials**
```yaml
# config/credentials.yml.enc
google:
  client_id: your-client-id.apps.googleusercontent.com
```

### Step 4: Set Receiver URL

```bash
export RISC_RECEIVER_URL=https://your-production-domain.com/risc/events
```

**Important**: The URL must be:
- HTTPS (required by Google)
- Publicly accessible
- On an authorized domain in your Google Cloud Project

### Step 5: Configure RISC Stream

Run the rake task to register your endpoint with Google:

```bash
bin/rails risc:configure
```

This will:
- Create an authorization token
- Register your webhook endpoint
- Subscribe to all event types
- Return success/failure status

### Step 6: Test the Integration

Send a test verification event:

```bash
bin/rails risc:test
```

Check your logs to confirm the verification event was received and processed.

### Step 7: Monitor Events

List recent security events:

```bash
bin/rails risc:list
```

View statistics:

```bash
bin/rails risc:stats
```

## Rake Tasks

### Configuration
```bash
# Register RISC endpoint with Google
bin/rails risc:configure

# Get current RISC stream configuration
bin/rails risc:status

# Send test verification event
bin/rails risc:test

# Enable RISC stream
bin/rails risc:enable

# Disable RISC stream
bin/rails risc:disable
```

### Monitoring
```bash
# List recent security events
bin/rails risc:list

# Show security event statistics
bin/rails risc:stats
```

### Maintenance
```bash
# Clean up expired security events (90+ days old)
bin/rails risc:cleanup
```

## Security Event Retention

Security events are automatically deleted after **90 days** as required by the RISC Terms of Service. The `SecurityEvent` model includes:

- `expires_at` field set to 90 days from creation
- `.expired` scope for finding events past retention period
- Rake task (`risc:cleanup`) for manual cleanup
- Consider adding a scheduled job for automatic cleanup

## Monitoring and Debugging

### Check Recent Events

```ruby
# In Rails console
SecurityEvent.recent.limit(10).each do |event|
  puts "#{event.created_at} - #{event.event_type_name} - #{event.reason}"
end
```

### Find Unprocessed Events

```ruby
SecurityEvent.unprocessed.each do |event|
  puts "Unprocessed: #{event.id} - #{event.event_type_name}"
end
```

### Find Events for a User

```ruby
user = User.find_by_email("user@example.com")
events = SecurityEvent.for_user(user)
```

### View Processing Errors

```ruby
SecurityEvent.where.not(processing_error: nil).each do |event|
  puts "Error in #{event.id}: #{event.processing_error}"
end
```

## Troubleshooting

### Webhook Not Receiving Events

1. **Check endpoint is publicly accessible**:
   ```bash
   curl -X POST https://your-domain.com/risc/events -d "test"
   ```

2. **Verify RISC stream is enabled**:
   ```bash
   bin/rails risc:status
   ```

3. **Check Rails logs** for errors:
   ```bash
   tail -f log/production.log | grep RISC
   ```

4. **Verify authorized domains** in Google Cloud Console

### Token Validation Failures

1. **Check OAuth client IDs are configured**:
   - Environment variable `GOOGLE_OAUTH_CLIENT_IDS`
   - Or Rails credentials `google.client_id`

2. **Verify service account has RISC admin role**

3. **Check token signature** (uses Google's public keys)

### Events Not Processing

1. **Check background job queue**:
   ```bash
   # View Mission Control dashboard
   open http://localhost:3000/admin/jobs
   ```

2. **Check for failed jobs**:
   ```ruby
   # In Rails console
   Solid Queue::FailedExecution.last(10)
   ```

3. **Manually process an event**:
   ```ruby
   event = SecurityEvent.unprocessed.first
   handler = RiscEventHandlerService.new(event.as_json.symbolize_keys)
   handler.process
   ```

## Admin Access

Admins can view security events in the Rails console or by querying the database:

```ruby
# All events
SecurityEvent.all

# Events by type
SecurityEvent.by_event_type(SecurityEvent::ACCOUNT_DISABLED)

# Events that required immediate action
SecurityEvent.all.select(&:requires_immediate_action?)
```

Consider adding an admin UI for viewing security events in `/admin/security_events`.

## Privacy and Compliance

- Security events contain minimal PII (Google subject ID only)
- Raw event data is **encrypted** using Lockbox
- Events are automatically deleted after **90 days**
- Only admins can view other users' security events
- Authorization enforced via SecurityEventPolicy

## Best Practices

1. **Monitor unprocessed events** regularly
2. **Set up alerts** for high-severity events (hijacking)
3. **Run cleanup task** weekly to delete expired events
4. **Test verification events** monthly to ensure webhook is working
5. **Log all security actions** for audit trail
6. **Review security events** during security incidents
7. **Keep service account credentials secure**

## References

- [Google Cross-Account Protection Docs](https://developers.google.com/identity/protocols/risc)
- [RISC Specification (OpenID Foundation)](https://openid.net/specs/openid-risc-profile-specification-1_0.html)
- [Security Event Tokens (RFC 8417)](https://tools.ietf.org/html/rfc8417)

## Next Steps

- [ ] Add admin UI for viewing security events
- [ ] Set up automated cleanup job (weekly)
- [ ] Configure monitoring alerts for critical events
- [ ] Document incident response procedures
- [ ] Consider adding Slack notifications for critical events
