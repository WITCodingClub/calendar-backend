# Dev Container Configuration

This directory contains the development container configuration for the WIT Calendar Backend project.

## Prerequisites

- [Visual Studio Code](https://code.visualstudio.com/)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)

## Getting Started

1. Open this project in VS Code
2. When prompted, click "Reopen in Container" (or use Command Palette: `Dev Containers: Reopen in Container`)
3. Wait for the container to build and start (first time takes a few minutes)
4. The post-create script will automatically:
   - Install Ruby gems
   - Create and migrate the database
   - Install JavaScript dependencies (if any)

## What's Included

### Services

- **app**: Rails development environment (Ruby 3.4.7)
- **postgres**: PostgreSQL 17 database
- **redis**: Redis 7 for sessions and caching

### VS Code Extensions

The following extensions are automatically installed:

- Ruby LSP (Shopify.ruby-lsp) - Ruby language server
- Ruby rdbg (KoichiSasada.vscode-rdbg) - Ruby debugger
- Tailwind CSS IntelliSense
- GitLens
- GitHub Copilot
- ERB tools and formatting

### Ports

The following ports are forwarded to your local machine:

- **3000**: Rails server
- **5432**: PostgreSQL
- **6379**: Redis

## Running the Application

After the container starts, you can:

```bash
# Start the Rails server with all processes
bin/dev

# Start Rails server only
bin/rails server

# Open Rails console
bin/rails console

# Run tests
bin/rails test
# or
rspec
```

## Database Management

```bash
# Create and migrate databases
bin/rails db:create db:migrate

# Reset database
bin/rails db:reset

# Run seeds
bin/rails db:seed
```

## Troubleshooting

### Container won't start

1. Make sure Docker Desktop is running
2. Try rebuilding the container: Command Palette → `Dev Containers: Rebuild Container`

### Database connection issues

The DATABASE_URL is automatically configured to connect to the postgres service. If you encounter issues:

```bash
# Check if postgres is running
pg_isready -h localhost -p 5432 -U postgres

# Check connection
psql $DATABASE_URL
```

### Redis connection issues

```bash
# Check if redis is running
redis-cli -h localhost -p 6379 ping
```

## Environment Variables

Environment variables are set in `.devcontainer/devcontainer.json` under `remoteEnv`. For local overrides, create a `.env` file in the project root (automatically copied from `.env.example` on first setup).

## Customization

- **devcontainer.json**: Main configuration, VS Code settings, and extensions
- **Dockerfile**: Container image definition and installed packages
- **docker-compose.yml**: Service definitions and dependencies
- **post-create.sh**: Setup script that runs after container creation
