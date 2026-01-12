# CI/CD Pipeline

## Overview

The project uses GitHub Actions for continuous integration and continuous deployment.

## Continuous Integration (CI)

**Workflow:** `.github/workflows/ci.yml`

Runs on: Pull requests to `main`, pushes to `main`

### Jobs

| Job | Description |
|-----|-------------|
| **lint** | Runs Rubocop for code style |
| **security** | Runs Brakeman for security scanning |
| **test** | Runs RSpec test suite |

All jobs run in parallel. The test job requires PostgreSQL (with pgvector) and Redis services.

## Continuous Deployment (CD)

**Workflow:** `.github/workflows/deploy.yml`

Runs on: Pushes to `main`, manual trigger (workflow_dispatch)

### Deployment Process

1. Connects to Tailscale network
2. SSHs into production server
3. Stops the running Rails server (Ctrl+C to screen session)
4. Pulls latest code
5. Runs database migrations
6. Restarts the server
7. Verifies deployment via health check

### Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `TAILSCALE_OAUTH_CLIENT_ID` | Tailscale OAuth client ID for GitHub Actions |
| `TAILSCALE_OAUTH_SECRET` | Tailscale OAuth client secret |
| `SERVER_HOST` | Tailscale hostname or IP of the production server |
| `SSH_PRIVATE_KEY` | SSH private key (ed25519) for connecting to server |

### Setting Up Tailscale OAuth

1. Go to [Tailscale Admin Console](https://login.tailscale.com/admin/settings/oauth)
2. Create a new OAuth client with:
   - Tags: `tag:ci`
   - Scopes: `devices:read`, `devices:write`
3. Copy the client ID and secret to GitHub secrets

### Setting Up SSH Key

1. Generate a new SSH key: `ssh-keygen -t ed25519 -f ci_deploy -C "github-actions-deploy"`
2. Add the public key to `~/.ssh/authorized_keys` on your server
3. Add the private key content to `SSH_PRIVATE_KEY` GitHub secret

### Screen Session

The server runs in a screen session named `witcal-prod-server`. The deployment uses screen commands to control the server process.

## Manual Deployment

You can manually trigger a deployment from the GitHub Actions tab by selecting the "Deploy" workflow and clicking "Run workflow".
