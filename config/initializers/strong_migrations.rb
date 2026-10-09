# frozen_string_literal: true

# strong_migrations stops a migration that can lock a busy table or break the
# running app. Production runs `bin/rails db:prepare` before Puma starts, so a
# migration that waits on a lock or fails takes the site down.

# Migrations up to this version ran before the gem was added. Do not check them.
StrongMigrations.start_after = 20261008223000

# Production runs PostgreSQL 17. The checks use this version, not the version of
# the local database.
StrongMigrations.target_version = 17

# Give up on a lock after 10 seconds, so a migration that waits behind a long
# query does not block every other query on the table.
StrongMigrations.lock_timeout = 10.seconds

# Stop a statement after 1 hour. Validating a foreign key scans the table.
StrongMigrations.statement_timeout = 1.hour
