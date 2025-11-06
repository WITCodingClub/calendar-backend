# Dev Container Setup

This document describes the Dev Container configuration for the WIT Calendar Backend project.

## Overview

The Dev Container setup provides a fully configured development environment running in Docker, eliminating the need to install Ruby, PostgreSQL, Redis, and other dependencies directly on your local machine.

## Architecture

### Services

The devcontainer runs three services:

1. **app**: The main Rails development container
   - Ruby 3.4.7 on Debian slim
   - All system dependencies pre-installed (build tools, PostgreSQL client, Redis tools, etc.)
   - VS Code extensions automatically installed
   - Non-root user (`vscode`) for security
   - Shares network with postgres service for simplified connectivity

2. **postgres**: PostgreSQL 17 database
   - Alpine Linux base for minimal footprint
   - Creates both `wit_calendar_backend_development` and `wit_calendar_backend_development_queue` databases
   - Persistent volume for data
   - Health checks enabled

3. **redis**: Redis 7 for session storage
   - Alpine Linux base
   - AOF (Append Only File) persistence enabled
   - Persistent volume for data
   - Health checks enabled

### Network Configuration

The app container uses `network_mode: service:postgres`, meaning:
- The app shares the postgres container's network namespace
- Both postgres and redis are accessible via `localhost` from the app
- Simplifies connection strings and eliminates Docker networking complexity
- Port forwarding (3000, 5432, 6379) makes services accessible on the host machine

## File Structure

```
.devcontainer/
├── devcontainer.json     # Main configuration
├── docker-compose.yml    # Service definitions
├── Dockerfile           # App container image
├── post-create.sh       # Setup script
└── README.md           # User documentation
```

### devcontainer.json

Configures:
- VS Code settings (Ruby LSP, formatters, rulers, etc.)
- Extensions to install (Ruby LSP, debugger, Tailwind CSS, etc.)
- Port forwarding and labels
- Post-creation and post-start commands
- Environment variables
- Dev container features (git, GitHub CLI, Node.js)

**Key Features Enabled:**
- `ghcr.io/devcontainers/features/git:1` - Git CLI
- `ghcr.io/devcontainers/features/github-cli:1` - GitHub CLI
- `ghcr.io/devcontainers/features/node:1` - Node.js LTS (for asset compilation)

**Environment Variables:**
- `DATABASE_URL`: Points to postgres service
- `REDIS_URL`: Points to redis service

### Dockerfile

The app container:
- Based on `ruby:3.4.7-slim`
- Installs system dependencies: PostgreSQL client, Redis tools, build tools, etc.
- Creates non-root `vscode` user (UID 1000, GID 1000)
- Grants sudo access to vscode user
- Installs `ruby-lsp` and `rdbg` gems globally for IDE support
- Configures git safe directory

### docker-compose.yml

Defines three services with proper health checks and dependencies:
- App depends on postgres and redis being healthy
- Uses named volumes for data persistence
- Mounts workspace at `/workspaces` (VS Code standard)
- App runs `sleep infinity` to keep container alive

### post-create.sh

Runs after container creation to:
1. Copy `.env.example` to `.env` if it doesn't exist
2. Run `bundle install`
3. Wait for PostgreSQL to be ready
4. Wait for Redis to be ready
5. Run `bin/rails db:create db:migrate`
6. Install npm packages if `package.json` exists

## VS Code Extensions

The following extensions are automatically installed:

### Ruby Development
- **Shopify.ruby-lsp**: Ruby language server (LSP) for IntelliSense, formatting, diagnostics
- **KoichiSasada.vscode-rdbg**: Ruby debugger integration

### Web Development
- **bradlc.vscode-tailwindcss**: Tailwind CSS IntelliSense

### General Development
- **eamodio.gitlens**: Enhanced Git integration
- **GitHub.copilot**: AI pair programmer (requires license)
- **GitHub.copilot-chat**: AI chat assistant (requires license)

### Utilities
- **formulahendry.auto-rename-tag**: Auto-rename paired HTML/ERB tags
- **naumovs.color-highlight**: Highlight color values
- **esbenp.prettier-vscode**: Code formatter for JavaScript/CSS
- **dbaeumer.vscode-eslint**: JavaScript linter
- **manuelpuyol.erb-linter**: ERB template linter
- **aliariff.vscode-erb-beautify**: ERB formatter

## Usage

### Starting the Dev Container

1. Open VS Code
2. Install the Dev Containers extension
3. Open this project
4. Command Palette → "Dev Containers: Reopen in Container"
5. Wait for build and post-create script (5-10 minutes first time)

### Rebuilding the Container

If you modify the devcontainer configuration:
- Command Palette → "Dev Containers: Rebuild Container"

### Running Rails

```bash
# Start all services (Rails + Solid Queue + CSS)
bin/dev

# Rails server only
bin/rails server

# Console
bin/rails console

# Tests
rspec
```

### Database Operations

```bash
# Create and migrate
bin/rails db:create db:migrate

# Reset database
bin/rails db:reset

# Check database connection
psql $DATABASE_URL
```

### Redis Operations

```bash
# Check Redis connection
redis-cli -h localhost -p 6379 ping

# Monitor Redis commands
redis-cli -h localhost -p 6379 monitor
```

## How It Works

1. **Container Launch**: VS Code starts the docker-compose services
2. **Health Checks**: Waits for postgres and redis to be healthy
3. **Post-Create**: Runs `post-create.sh` to set up the environment
4. **Post-Start**: Runs `bin/rails db:prepare` on subsequent starts
5. **Ready**: Terminal opens in the app container, ready to run Rails commands

## Advantages

- **Consistency**: Every developer has identical environment
- **Isolation**: No conflicts with other projects or system Ruby
- **Speed**: No need to install dependencies locally
- **Simplicity**: Single command to get started
- **Portability**: Works on macOS, Linux, and Windows (WSL2)

## Limitations

- **First Build**: Takes 5-10 minutes to download images and build
- **Docker Required**: Must have Docker Desktop installed and running
- **Resource Usage**: Uses ~2-4GB RAM for all services
- **File I/O**: Slight performance impact on file operations (mitigated by cached volumes)

## Troubleshooting

### "Cannot connect to Docker daemon"
- Ensure Docker Desktop is running
- Check Docker Desktop settings allow the Dev Containers extension

### "Port already in use"
- Stop any local PostgreSQL/Redis services
- Or change ports in `docker-compose.yml`

### "Database connection failed"
- Check postgres health: `docker compose ps`
- View postgres logs: `docker compose logs postgres`
- Try manual connection: `psql -h localhost -U postgres`

### "Gems not installing"
- Rebuild container: Command Palette → "Rebuild Container"
- Check Gemfile.lock for platform issues
- Try: `bundle lock --add-platform x86_64-linux`

### "VS Code extensions not working"
- Reload window: Command Palette → "Developer: Reload Window"
- Rebuild container: Command Palette → "Rebuild Container"
- Check extension logs in Output panel

## Performance Optimization

### File I/O Performance

The docker-compose uses `:cached` mount for the workspace:
```yaml
volumes:
  - ../..:/workspaces:cached
```

This improves file I/O performance by allowing the container's view to be temporarily inconsistent with the host.

### Resource Limits

You can add resource limits to services in `docker-compose.yml`:
```yaml
app:
  deploy:
    resources:
      limits:
        cpus: '2'
        memory: 2G
```

## Security Considerations

- **Non-root user**: All commands run as `vscode` user (UID 1000)
- **Sudo access**: vscode user has passwordless sudo for system operations
- **Credentials**: `.env` file is not committed (in `.gitignore`)
- **Network isolation**: Services only expose necessary ports
- **Data persistence**: Database volumes persist between container rebuilds

## Future Improvements

Potential enhancements:
- [ ] Add Chrome/Firefox for system testing
- [ ] Pre-install common debugging tools
- [ ] Add performance monitoring tools
- [ ] Include database GUI (pgAdmin or similar)
- [ ] Add Redis GUI (RedisInsight or similar)
- [ ] Configure remote debugging
- [ ] Add staging environment simulation
