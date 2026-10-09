# Run using bin/ci
#
# These steps match .github/workflows/ci.yml. The test steps need
# HASHID_SALT and the POSTGRES_* variables (see CLAUDE.md).

CI.run do
  step "Style: Ruby", "bin/rubocop"

  step "Style: ERB", "npx --yes @herb-tools/linter"

  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Importmap audit", "bin/importmap audit"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"

  step "Boot: Zeitwerk check", "bin/rails zeitwerk:check"

  step "Build: Tailwind CSS", "env RAILS_ENV=test bin/rails tailwindcss:build"
  step "Tests: Prepare database", "env RAILS_ENV=test bin/rails db:test:prepare"
  step "Tests: RSpec", "env RAILS_ENV=test bundle exec rspec"
end
