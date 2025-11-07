# Rate Limiting

This document describes the rate limiting implementation in the calendar backend using Rack::Attack.

## Overview

Rate limiting protects the application from abuse, denial-of-service attacks, and ensures fair resource allocation among users. The system uses Redis-backed rate limiting with Rack::Attack to enforce various limits across different endpoints.

## Architecture

- **Storage**: Redis (shared with cache)
- **Middleware**: Rack::Attack + custom RateLimitHeadersMiddleware
- **Response Headers**: RFC-compliant rate limit headers on all responses
- **Configuration**: `config/initializers/rack_attack.rb`

## Rate Limit Headers

All responses include the following headers (when applicable):

- `RateLimit-Limit`: Maximum number of requests allowed in the period
- `RateLimit-Remaining`: Number of requests remaining in the current period
- `RateLimit-Reset`: Unix timestamp when the rate limit resets

When rate limited (HTTP 429):
- `Retry-After`: Number of seconds to wait before retrying

## Safelists (No Rate Limiting)

The following endpoints are exempt from rate limiting:

- **Health checks**: `/up`, `/healthchecks/*`, `/okcomputer`
- **Static assets**: `/assets/*`, `/packs/*`, `/rails/active_storage/*`
- **Localhost in development**: `127.0.0.1`, `::1`

## Blocklists (Immediate Block)

### Suspicious Request Patterns (Fail2Ban)
- **Trigger**: 5 suspicious requests within 10 minutes
- **Ban duration**: 1 hour
- **Patterns**:
  - Path traversal attempts (`../`, `/etc/passwd`)
  - WordPress admin attempts (`/wp-admin`, `/wp-login`)
  - phpMyAdmin attempts
  - Environment file access (`.env`)

### Suspicious User Agents
Blocked immediately:
- Empty user agents
- User agents containing "scraper", "crawler"
- User agents containing "bot" (except Googlebot)

## Global Throttles

### General IP-based Throttle
- **Limit**: 300 requests per 5 minutes
- **Scope**: Per IP address
- **Excludes**: Static assets, safelisted paths

## Authentication Throttles

### Login Attempts (By Email)
- **Limit**: 5 attempts per 20 seconds
- **Scope**: Per email address (normalized: lowercase, no whitespace)
- **Prevents**: Credential stuffing attacks

### Login Attempts (By IP)
- **Limit**: 20 attempts per 5 minutes
- **Scope**: Per IP address
- **Prevents**: Distributed brute force attacks

### Password Resets (By Email)
- **Limit**: 3 attempts per 20 minutes
- **Scope**: Per email address

### Password Resets (By IP)
- **Limit**: 10 attempts per 20 minutes
- **Scope**: Per IP address

## OAuth Throttles

### OAuth Callbacks
- **Limit**: 10 requests per minute
- **Scope**: Per IP address
- **Endpoints**: `/auth/*`, `/oauth/*`
- **Purpose**: Prevent OAuth flow abuse

## API Throttles

### Authenticated Users
- **Limit**: 100 requests per minute
- **Scope**: Per user (via JWT token)
- **Endpoints**: All `/api/*` endpoints
- **Purpose**: Generous limit for legitimate API usage

### Unauthenticated Requests
- **Limit**: 20 requests per minute
- **Scope**: Per IP address
- **Endpoints**: All `/api/*` endpoints without valid JWT
- **Purpose**: Strict limit to prevent API abuse

### Course Processing (Expensive Operation)
- **Limit**: 5 requests per minute
- **Scope**: Per user
- **Endpoint**: `POST /api/process_courses`
- **Purpose**: Protect expensive web scraping and API operations

### Template Preview (Expensive Operation)
- **Limit**: 10 requests per minute
- **Scope**: Per user
- **Endpoint**: `POST /api/calendar_preferences/preview`
- **Purpose**: Protect computationally expensive Liquid template rendering

## Calendar Feed Throttles

### By Token
- **Limit**: 60 requests per hour
- **Scope**: Per calendar token
- **Endpoint**: `GET /calendar/:calendar_token`
- **Purpose**: Allow reasonable calendar app polling while preventing abuse

### By IP (Backup)
- **Limit**: 100 requests per hour
- **Scope**: Per IP address
- **Endpoint**: `GET /calendar/:calendar_token`
- **Purpose**: Additional protection against token rotation abuse

## Admin Area Throttles

### General Admin Requests
- **Limit**: 200 requests per 5 minutes
- **Scope**: Per session ID
- **Endpoints**: All `/admin/*` routes
- **Purpose**: More generous than public API for admin workflows

### Destructive Operations
- **Limit**: 20 requests per minute
- **Scope**: Per session ID
- **Endpoints**: DELETE requests and revoke/destroy actions in `/admin/*`
- **Purpose**: Prevent accidental or malicious bulk deletions

## Custom Error Responses

### Rate Limited (429)
```json
{
  "error": "Rate limit exceeded",
  "message": "Too many requests. Please try again later.",
  "retry_after": 300
}
```

### Blocked (403)
```json
{
  "error": "Forbidden",
  "message": "Request blocked"
}
```

## JWT Token Extraction

For API rate limiting by user, tokens are extracted and decoded without verification:

```ruby
Authorization: Bearer <jwt_token>
```

The `user_id` claim is used for per-user rate limiting. Authentication is still enforced by controllers.

## Testing Rate Limits

```bash
# Test basic rate limit
for i in {1..301}; do curl http://localhost:3000/users/sign_in; done

# Test API rate limit with authentication
for i in {1..101}; do curl -H "Authorization: Bearer TOKEN" http://localhost:3000/api/user/email; done

# Test course processing limit
for i in {1..6}; do curl -X POST -H "Authorization: Bearer TOKEN" http://localhost:3000/api/process_courses; done
```

## Monitoring

Rate limit violations are logged by Rack::Attack. Monitor:

- Redis memory usage (rate limit counters)
- 429 response rates
- IP addresses generating repeated 429s
- Fail2Ban bans (check Redis keys with pattern `rack::attack:*`)

## Production Considerations

1. **Redis Persistence**: Rate limit data is ephemeral by design, so Redis persistence is not required for rate limiting alone
2. **Redis Capacity**: Plan for ~1KB per active rate limit key. With 10,000 active users, expect ~10MB
3. **Distributed Systems**: Rate limits are per-Redis-instance. In multi-server setups, ensure shared Redis
4. **Cloudflare/CDN**: Consider offloading some rate limiting to CDN layer for DDoS protection
5. **Adjusting Limits**: Monitor real usage patterns and adjust limits in `config/initializers/rack_attack.rb`

## Bypassing Rate Limits (For Testing)

In development, localhost is automatically safelisted. In other environments:

```ruby
# In Rails console
Rack::Attack.cache.store.clear  # Clear all rate limit counters
```

## Related Files

- `config/initializers/rack_attack.rb` - Rate limiting configuration
- `app/middleware/rate_limit_headers_middleware.rb` - Response header middleware
- `spec/requests/rack_attack_spec.rb` - Rate limiting tests
- `config/application.rb` - Middleware configuration

## References

- [Rack::Attack Documentation](https://github.com/rack/rack-attack)
- [IETF Rate Limit Headers Draft](https://datatracker.ietf.org/doc/html/draft-ietf-httpapi-ratelimit-headers)
