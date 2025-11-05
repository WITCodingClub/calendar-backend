# frozen_string_literal: true

namespace :oauth do
  desc "Revoke and delete OAuth credential by email"
  task :revoke, [:email] => :environment do |_t, args|
    email = args[:email]

    if email.blank?
      puts "Usage: rake oauth:revoke[user@example.com]"
      exit 1
    end

    credential = OauthCredential.find_by(email: email)

    if credential.nil?
      puts "No credential found for #{email}"
      exit 1
    end

    puts "Found credential for #{email} (User: #{credential.user.email})"
    puts "Provider: #{credential.provider}"
    puts "Created: #{credential.created_at}"

    # Use the job to revoke (synchronously for rake tasks)
    RevokeOauthCredentialJob.perform_now(credential.id)
    puts "✓ Revoked and deleted credential for #{email}"
  end

  desc "Revoke and delete all OAuth credentials for a user"
  task :revoke_user, [:user_email] => :environment do |_t, args|
    user_email = args[:user_email]

    if user_email.blank?
      puts "Usage: rake oauth:revoke_user[user@example.com]"
      exit 1
    end

    user = User.find_by(email: user_email)

    if user.nil?
      puts "No user found with email #{user_email}"
      exit 1
    end

    credentials = user.oauth_credentials

    if credentials.empty?
      puts "User #{user_email} has no OAuth credentials"
      exit 0
    end

    puts "Found #{credentials.count} credential(s) for user #{user_email}:"
    credentials.each do |cred|
      puts "  - #{cred.email} (#{cred.provider})"
    end

    credentials.each do |credential|
      puts "\nRevoking #{credential.email}..."
      RevokeOauthCredentialJob.perform_now(credential.id)
      puts "✓ Revoked and deleted credential for #{credential.email}"
    end

    puts "\n✓ All credentials revoked for user #{user_email}"
  end

  desc "List all OAuth credentials"
  task list: :environment do
    credentials = OauthCredential.includes(:user).order(created_at: :desc)

    if credentials.empty?
      puts "No OAuth credentials found"
      exit 0
    end

    puts "Total OAuth credentials: #{credentials.count}\n"
    puts "%-40s %-30s %-10s %s" % ["OAuth Email", "User Email", "Provider", "Created"]
    puts "-" * 100

    credentials.each do |cred|
      puts "%-40s %-30s %-10s %s" % [
        cred.email,
        cred.user.email,
        cred.provider,
        cred.created_at.strftime("%Y-%m-%d %H:%M")
      ]
    end
  end

  desc "Revoke a specific OAuth credential by ID"
  task :revoke_by_id, [:id] => :environment do |_t, args|
    id = args[:id]

    if id.blank?
      puts "Usage: rake oauth:revoke_by_id[123]"
      exit 1
    end

    credential = OauthCredential.find_by(id: id)

    if credential.nil?
      puts "No credential found with ID #{id}"
      exit 1
    end

    puts "Found credential:"
    puts "  ID: #{credential.id}"
    puts "  Email: #{credential.email}"
    puts "  User: #{credential.user.email}"
    puts "  Provider: #{credential.provider}"

    RevokeOauthCredentialJob.perform_now(credential.id)
    puts "✓ Revoked and deleted credential (ID: #{id})"
  end

  desc "Check token status for an OAuth credential"
  task :check, [:email] => :environment do |_t, args|
    email = args[:email]

    if email.blank?
      puts "Usage: rake oauth:check[user@example.com]"
      exit 1
    end

    credential = OauthCredential.find_by(email: email)

    if credential.nil?
      puts "No credential found for #{email}"
      exit 1
    end

    puts "OAuth Credential Details:"
    puts "  Email: #{credential.email}"
    puts "  User: #{credential.user.email}"
    puts "  Provider: #{credential.provider}"
    puts "  UID: #{credential.uid}"
    puts "  Expires at: #{credential.token_expires_at}"
    puts "  Expired?: #{credential.token_expired?}"
    puts "  Has refresh token?: #{credential.refresh_token.present?}"
    puts "  Created: #{credential.created_at}"
    puts "  Updated: #{credential.updated_at}"

    if credential.google_calendar
      puts "\nAssociated Google Calendar:"
      puts "  Calendar ID: #{credential.google_calendar.google_calendar_id}"
      puts "  Summary: #{credential.google_calendar.summary}"
      puts "  Events count: #{credential.google_calendar.google_calendar_events.count}"
    else
      puts "\nNo associated Google Calendar"
    end
  end
end
