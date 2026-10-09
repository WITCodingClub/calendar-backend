# frozen_string_literal: true

# Backfill for #713. OauthCredential encrypts access_token and refresh_token,
# but rows saved before that change hold plain text. Production ran it on
# 2026-10-09. A local database with older rows still needs it.
# Safe to run again: a row whose tokens are already ciphertext is skipped.
# The task never prints a token.
namespace :oauth_credentials do
  desc "Encrypt OAuth tokens that are still stored in plain text (safe to run again)"
  task encrypt: :environment do
    attributes = OauthCredential.encrypted_attributes.to_a
    total      = OauthCredential.count
    encrypted  = 0
    skipped    = 0
    failed     = 0

    puts "Checking #{total} OAuth credential(s)."

    # The app turns support_unencrypted_data off, so a plain-text row raises
    # on read. Only this task reads those rows, to rewrite them.
    encryption_config = ActiveRecord::Encryption.config
    support_was = encryption_config.support_unencrypted_data
    encryption_config.support_unencrypted_data = true

    begin
      OauthCredential.find_each.with_index(1) do |credential, index|
        plain = attributes.any? do |attribute|
          credential.public_send(attribute).present? && !credential.encrypted_attribute?(attribute)
        end

        if plain
          # update_columns: no callbacks run and updated_at does not change.
          credential.encrypt
          encrypted += 1
        else
          skipped += 1
        end
      rescue ActiveRecord::ActiveRecordError, ActiveRecord::Encryption::Errors::Base => e
        failed += 1
        puts "\n  Credential #{credential.id}: #{e.class}"
      ensure
        print "  #{index}/#{total}\r"
      end
    ensure
      encryption_config.support_unencrypted_data = support_was
    end

    puts "\nEncrypted #{encrypted}. Already encrypted #{skipped}. Failed #{failed}."
    abort "Some credentials were not encrypted. Run the task again after you fix the cause." if failed.positive?
  end
end
