# Calendar Backend Documentation

Welcome to the Calendar Backend documentation! This guide will help you find the information you need.

## Quick Navigation

- **[Quick Reference](./QUICK_REFERENCE.md)** - Cheat sheet for common tasks, API endpoints, and template variables

## Getting Started

### Setup & Configuration
- **[DevContainer Setup](./setup/devcontainer-setup.md)** - Set up your development environment using DevContainers

## Core Features

### Calendar Preferences
Customize how course events appear in Google Calendar with templates, colors, and reminders.

- **[Calendar Preferences Architecture](./calendar-preferences/calendar_preferences.md)** - System architecture and design
- **[API Reference](./calendar-preferences/api_calendar_preferences.md)** - Complete API documentation
- **[Template Variables Guide](./calendar-preferences/template_variables.md)** - All available template variables and examples
- **[Extension Integration Guide](./calendar-preferences/extension_integration_guide.md)** - How to integrate with Chrome extensions

**Use Cases:**
- Backend developers: Start with Architecture
- Extension developers: Read Integration Guide → API Reference → Template Variables
- Quick reference: See [QUICK_REFERENCE.md](./QUICK_REFERENCE.md)

### Calendar Synchronization
Smart syncing between course schedules and Google Calendar.

- **[Intelligent Calendar Sync](./calendar-sync/intelligent_calendar_sync.md)** - Change detection and optimization
- **[Nightly Calendar Sync](./calendar-sync/nightly-calendar-sync.md)** - Automated background synchronization
- **[Google Calendar Events](./calendar-sync/google_calendar_events.md)** - Event creation and management
- **[User Google Calendar Edits](./calendar-sync/user_google_calendar_edits.md)** - Handling user modifications
- **[Multi-Email OAuth](./calendar-sync/multi-email-google-calendar-oauth.md)** - OAuth setup for multiple Google accounts
- **[OAuth Credential Management API](./calendar-sync/oauth-credential-management-api.md)** - API for managing connected Google accounts

**Use Cases:**
- Understanding sync performance: See Intelligent Calendar Sync
- Setting up automated syncs: See Nightly Calendar Sync
- OAuth configuration: See Multi-Email OAuth
- Managing connected accounts: See OAuth Credential Management API

### Embeddings & AI
Vector embeddings and semantic search capabilities.

- **[pgvector Embeddings](./embeddings/pgvector-embeddings.md)** - Vector database setup and usage
- **[Future Embedding Use Cases](./embeddings/future-embedding-use-cases.md)** - Planned AI features

**Use Cases:**
- Setting up vector search: See pgvector Embeddings
- Understanding AI roadmap: See Future Use Cases

## Integrations

- **[Rate My Professor](./integrations/rate-my-professor-integration.md)** - Integration with RateMyProfessor data

## Infrastructure

- **[Job Queues](./infrastructure/job-queues.md)** - Background job processing with ActiveJob

**Use Cases:**
- Adding background jobs: See Job Queues
- Understanding async processing: See Job Queues

## Security

- **[Cross-Account Protection (RISC)](./security/cross-account-protection.md)** - Google security event notifications and response
- **[Rate Limiting](./security/rate-limiting.md)** - Rate limiting and DDoS protection with Rack::Attack
- **[Authorization](./authorization.md)** - Role-based access control with Pundit

**Use Cases:**
- Setting up Google security events: See Cross-Account Protection
- Responding to account compromises: See Cross-Account Protection
- Understanding rate limits: See Rate Limiting
- Configuring rate limits: See Rate Limiting
- Adding authorization: See Authorization

## Documentation Map

```
docs/
├── README.md (you are here)
├── QUICK_REFERENCE.md (quick cheat sheet)
│
├── setup/
│   └── devcontainer-setup.md
│
├── calendar-preferences/
│   ├── calendar_preferences.md (architecture)
│   ├── api_calendar_preferences.md (API docs)
│   ├── template_variables.md (template guide)
│   └── extension_integration_guide.md (extension integration)
│
├── calendar-sync/
│   ├── intelligent_calendar_sync.md (sync optimization)
│   ├── nightly-calendar-sync.md (automated sync)
│   ├── google_calendar_events.md (event management)
│   ├── user_google_calendar_edits.md (user modifications)
│   ├── multi-email-google-calendar-oauth.md (OAuth setup)
│   └── oauth-credential-management-api.md (account management API)
│
├── embeddings/
│   ├── pgvector-embeddings.md (vector database)
│   └── future-embedding-use-cases.md (AI roadmap)
│
├── integrations/
│   └── rate-my-professor-integration.md
│
├── infrastructure/
│   └── job-queues.md
│
└── security/
    ├── cross-account-protection.md (Google RISC)
    └── rate-limiting.md
```

## Common Workflows

### I want to...

**Set up my development environment**
→ [DevContainer Setup](./setup/devcontainer-setup.md)

**Understand calendar preferences**
→ [Calendar Preferences Architecture](./calendar-preferences/calendar_preferences.md)

**Build a Chrome extension**
→ [Extension Integration Guide](./calendar-preferences/extension_integration_guide.md)

**Use the calendar preferences API**
→ [API Reference](./calendar-preferences/api_calendar_preferences.md)

**Customize event titles/descriptions**
→ [Template Variables Guide](./calendar-preferences/template_variables.md)

**Optimize calendar sync performance**
→ [Intelligent Calendar Sync](./calendar-sync/intelligent_calendar_sync.md)

**Set up automated nightly syncs**
→ [Nightly Calendar Sync](./calendar-sync/nightly-calendar-sync.md)

**Configure Google OAuth**
→ [Multi-Email OAuth](./calendar-sync/multi-email-google-calendar-oauth.md)

**Manage connected Google accounts**
→ [OAuth Credential Management API](./calendar-sync/oauth-credential-management-api.md)

**Add background jobs**
→ [Job Queues](./infrastructure/job-queues.md)

**Implement semantic search**
→ [pgvector Embeddings](./embeddings/pgvector-embeddings.md)

**Integrate RateMyProfessor data**
→ [Rate My Professor Integration](./integrations/rate-my-professor-integration.md)

**Configure rate limiting**
→ [Rate Limiting](./security/rate-limiting.md)

**Set up authorization policies**
→ [Authorization](./authorization.md)

**Configure Google security event notifications**
→ [Cross-Account Protection (RISC)](./security/cross-account-protection.md)

## Need Help?

1. Check the [Quick Reference](./QUICK_REFERENCE.md) for common tasks
2. Browse the relevant category above
3. Search for keywords in the documentation
4. Open an issue on GitHub
