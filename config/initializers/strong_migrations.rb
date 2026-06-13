# frozen_string_literal: true

StrongMigrations.start_after = 20251026214006

StrongMigrations.lock_timeout = 10.seconds
StrongMigrations.statement_timeout = 1.hour

StrongMigrations.auto_analyze = true
StrongMigrations.alphabetize_schema = true
StrongMigrations.remove_invalid_indexes = true
