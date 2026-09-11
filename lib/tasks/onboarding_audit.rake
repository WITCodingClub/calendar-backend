# frozen_string_literal: true

namespace :onboarding do
  desc "Report accounts that cannot onboard once a WIT Google account is required. " \
       "Read only. Pass SHOW_EMAILS=1 to list the addresses."

  task audit: :environment do
    total    = User.count
    stranded = User.where.not("LOWER(email) LIKE ?", "%@#{User::WIT_EMAIL_DOMAIN}").order(:created_at)

    puts "Onboarding audit"
    puts "=" * 60
    puts "Accounts in total:                  #{total}"
    puts "Keyed to an @#{User::WIT_EMAIL_DOMAIN} address:        #{total - stranded.count}"
    puts "Keyed to something else:            #{stranded.count}"
    puts

    if stranded.none?
      puts "Every account resolves. Nobody is stranded by the new rule."
      next
    end

    # The old endpoint minted an account for whatever email string it was sent,
    # so these exist. Onboarding now matches only a Google-verified @wit.edu
    # address, which means none of these accounts can be reached again — their
    # owner would land on a new, empty account instead.
    puts "These accounts cannot be reached by the new onboarding flow."
    puts "Their owners would get a fresh account, losing what is listed here."
    puts

    stranded.find_each do |user|
      label = ENV["SHOW_EMAILS"] == "1" ? user.email : "#{user.email.to_s[0, 3]}…@#{user.email.to_s.split('@').last}"

      puts "  #{user.public_id}  #{label}"
      puts "    created      #{user.created_at.to_date}"
      puts "    enrollments  #{user.enrollments.count}"
      puts "    calendars    #{user.google_calendars.count}"
      puts "    linked gmail #{user.oauth_credentials.where(provider: 'google').pluck(:email).join(', ').presence || 'none'}"
      puts
    end

    puts "-" * 60
    puts "A linked Google address ending in @#{User::WIT_EMAIL_DOMAIN} is the safe way to"
    puts "repoint one of these: that address was verified through OAuth, so"
    puts "updating the account's email to it does not trust anything unverified."
    puts "Run with SHOW_EMAILS=1 to see the full addresses." unless ENV["SHOW_EMAILS"] == "1"
  end
end
