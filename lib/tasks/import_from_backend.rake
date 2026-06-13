# frozen_string_literal: true

namespace :import do
  desc <<~DESC
    Import all user data from the old backend database.

    Required env vars:
      BACKEND_DATABASE_URL  PostgreSQL connection URL for the old backend DB

    Optional env vars:
      DRY_RUN=true          Print what would happen without writing anything
      SEND_WELCOME_EMAILS=true  Send password-reset email to each new user

    Example:
      BACKEND_DATABASE_URL=postgresql://... bin/rails import:from_backend
      BACKEND_DATABASE_URL=postgresql://... DRY_RUN=true bin/rails import:from_backend
  DESC
  task from_backend: :environment do
    url = ENV["BACKEND_DATABASE_URL"]
    abort "ERROR: BACKEND_DATABASE_URL is required" if url.blank?

    ImportFromBackendService.call(
      database_url: url,
      dry_run: ENV["DRY_RUN"].present?,
      send_welcome_emails: ENV["SEND_WELCOME_EMAILS"].present?
    )
  end
end
