# API Documentation

## Overview
This project uses automated API documentation generation from RSpec request specs. The documentation is automatically generated using `rspec-openapi` and served via Swagger UI using `rswag-api` and `rswag-ui`.

## Generating Documentation

### Automatic Generation (CI/CD)
Documentation is automatically generated from request specs in `spec/requests/api/` when changes are pushed to the `main` branch. The GitHub Actions workflow (`.github/workflows/update-api-docs.yml`) will:

1. Run all API request specs with `OPENAPI=1`
2. Merge the generated documentation
3. Commit and push the updated `doc/openapi.yaml` file

**Setup Requirements:**
To enable automatic documentation updates, you need to set up a deploy key:

1. Generate an SSH key pair:
   ```bash
   ssh-keygen -N "" -f deploy_key -C "github-actions"
   ```

2. Add the private key as a repository secret:
   - Go to Settings → Secrets and variables → Actions
   - Create a new secret named `PUSH_KEY`
   - Paste the contents of `deploy_key` (private key)

3. Add the public key as a deploy key:
   - Go to Settings → Deploy keys
   - Add a new deploy key with title `GitHub Actions`
   - Paste the contents of `deploy_key.pub` (public key)
   - ✅ Check "Allow write access"

### Manual Generation
To generate or update the documentation manually, run your request specs with the `OPENAPI` environment variable set:

```bash
OPENAPI=1 bundle exec rspec spec/requests/api
```

This will generate/update the `doc/openapi.yaml` file.

## Viewing Documentation

### Swagger UI
The API documentation is accessible via Swagger UI at the `/admin/api-docs` route.

**Important:** The documentation is protected by the admin authentication constraint. You must be logged in as an admin to access it.

### Accessing the Documentation
1. Start your Rails server: `bin/rails server`
2. Log in to the admin area (you need admin access)
3. Navigate to `http://localhost:3000/admin/api-docs`
4. Browse the interactive API documentation

The documentation is protected using the same `AdminConstraint` that secures the rest of the admin area (config/routes.rb:322).

## Configuration

### Request Headers
The following headers are documented for API requests (config/initializers/rspec_openapi.rb:8):
- `access-token`
- `uid`
- `client`

### Response Headers
The following headers are documented in API responses (config/initializers/rspec_openapi.rb:11):
- `access-token`
- `expiry`
- `token-type`
- `uid`
- `client`

### Ignoring Specs
To exclude specific specs from the documentation, add the `openapi: false` option:

```ruby
describe 'GET /api/internal/status', openapi: false do
  # This spec will not appear in the API documentation
end
```

## Parallel Test Support
The configuration supports parallel test execution. When running specs with `parallel_tests`, each thread generates its own documentation file which can be merged later.

## File Structure
- **Generated docs:** `doc/openapi.yaml`
- **Configuration:**
  - `config/initializers/rspec_openapi.rb` - Main configuration
  - `config/initializers/rswag_api.rb` - API serving configuration
  - `config/initializers/rswag_ui.rb` - Swagger UI configuration
- **Routes:** `config/routes.rb:369-370` - Mounts Swagger UI and API engines inside admin namespace
- **CI/CD:**
  - `.github/workflows/update-api-docs.yml` - Automatic documentation generation workflow
  - `bin/merge-api-docs.rb` - Script to merge parallel OpenAPI documentation files

## Best Practices

1. **Write comprehensive request specs** - The quality of your documentation depends on your spec coverage
2. **Use descriptive test names** - These become operation summaries in the documentation
3. **Test all response codes** - Document success and error responses
4. **Include examples** - Provide realistic request/response examples in your specs
5. **Update regularly** - Regenerate docs when you add new endpoints or modify existing ones

## Troubleshooting

### Documentation not updating
- Ensure the `doc` directory exists
- Run specs with `OPENAPI=1` to force regeneration
- Check that specs are in `spec/requests/api/` directory

### Missing endpoints
- Ensure request specs exist for the endpoints
- Verify specs don't have `openapi: false` flag
- Check that specs are actually running (not skipped or pending)
