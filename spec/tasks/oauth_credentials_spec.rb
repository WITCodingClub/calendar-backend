# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "oauth_credentials rake tasks" do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  def run_task(name)
    task = Rake::Task[name]
    task.reenable
    task.invoke
  end

  def stored(credential, column)
    OauthCredential.connection.select_value(
      OauthCredential.where(id: credential.id).select(column).to_sql
    )
  end

  # A row saved before the model encrypted its tokens. Raw SQL, because any
  # Active Record write would encrypt the values.
  def legacy_credential(access_token:, refresh_token:)
    create(:oauth_credential).tap do |credential|
      OauthCredential.connection.update(OauthCredential.sanitize_sql_array([
        "UPDATE oauth_credentials SET access_token = ?, refresh_token = ? WHERE id = ?",
        access_token, refresh_token, credential.id
      ]))
    end
  end

  describe "oauth_credentials:encrypt" do
    it "encrypts plain-text tokens and keeps their values" do
      legacy = legacy_credential(access_token: "synthetic-legacy-access", refresh_token: "synthetic-legacy-refresh")

      expect { run_task("oauth_credentials:encrypt") }.to output(/Encrypted 1\. Already encrypted 0\. Failed 0\./).to_stdout

      expect(stored(legacy, :access_token)).not_to include("synthetic-legacy-access")
      expect(stored(legacy, :refresh_token)).not_to include("synthetic-legacy-refresh")
      expect(OauthCredential.find(legacy.id))
        .to have_attributes(access_token: "synthetic-legacy-access", refresh_token: "synthetic-legacy-refresh")
    end

    it "encrypts a row with no refresh token and leaves the column NULL" do
      legacy = legacy_credential(access_token: "synthetic-legacy-access", refresh_token: nil)

      expect { run_task("oauth_credentials:encrypt") }.to output(/Encrypted 1\./).to_stdout

      expect(ActiveRecord::Encryption.encryptor.encrypted?(stored(legacy, :access_token))).to be(true)
      expect(stored(legacy, :refresh_token)).to be_nil
    end

    it "is safe to run twice: the second run changes nothing" do
      legacy = legacy_credential(access_token: "synthetic-legacy-access", refresh_token: "synthetic-legacy-refresh")
      current = create(:oauth_credential, access_token: "synthetic-current-access")

      expect { run_task("oauth_credentials:encrypt") }.to output(/Encrypted 1\. Already encrypted 1\./).to_stdout
      ciphertext = stored(legacy, :access_token)

      expect { run_task("oauth_credentials:encrypt") }.to output(/Encrypted 0\. Already encrypted 2\./).to_stdout
      expect(stored(legacy, :access_token)).to eq(ciphertext)
      expect(OauthCredential.find(current.id).access_token).to eq("synthetic-current-access")
    end

    it "does not run the model callbacks or touch updated_at" do
      legacy = legacy_credential(access_token: "synthetic-legacy-access", refresh_token: "synthetic-legacy-refresh")
      legacy.update_columns(updated_at: 10.days.ago, metadata: { "token_revoked" => true })
      updated_at = legacy.reload.updated_at

      expect { run_task("oauth_credentials:encrypt") }.to output(/Encrypted 1\./).to_stdout

      expect(FriendMeetings::ResumeJob).not_to have_been_enqueued
      expect(legacy.reload.updated_at).to eq(updated_at)
      expect(legacy).to be_token_revoked
    end

    it "turns support_unencrypted_data back off after the run" do
      legacy_credential(access_token: "synthetic-legacy-access", refresh_token: nil)

      expect { run_task("oauth_credentials:encrypt") }.to output(/Encrypted 1\./).to_stdout

      expect(ActiveRecord::Encryption.config.support_unencrypted_data).to be(false)
    end

    it "never prints a token" do
      legacy_credential(access_token: "synthetic-legacy-access", refresh_token: "synthetic-legacy-refresh")

      expect { run_task("oauth_credentials:encrypt") }.not_to output(/synthetic-legacy/).to_stdout
    end
  end
end
