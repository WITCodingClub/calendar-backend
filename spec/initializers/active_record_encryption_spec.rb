# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActiveRecordEncryptionKeys do
  let(:all_env) do
    {
      "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY" => "synthetic-primary",
      "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY" => "synthetic-deterministic",
      "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT" => "synthetic-salt"
    }
  end
  let(:no_credentials) { {} }

  describe ".missing" do
    it "is empty when every key is in ENV" do
      expect(described_class.missing(env: all_env, credentials: no_credentials)).to be_empty
    end

    it "names each env var that neither ENV nor credentials give" do
      env = all_env.except("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY", "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT")

      expect(described_class.missing(env: env, credentials: no_credentials))
        .to eq(%w[ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT])
    end

    it "accepts a key from credentials when ENV has none" do
      credentials = { active_record_encryption: { primary_key: "synthetic-primary",
                                                  deterministic_key: "synthetic-deterministic",
                                                  key_derivation_salt: "synthetic-salt" } }

      expect(described_class.missing(env: {}, credentials: credentials)).to be_empty
    end

    it "treats a blank env var as missing" do
      env = all_env.merge("ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY" => "")

      expect(described_class.missing(env: env, credentials: no_credentials))
        .to eq(%w[ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY])
    end
  end

  describe ".verify!" do
    it "raises with the names of the missing env vars" do
      expect { described_class.verify!(env: {}, credentials: no_credentials) }
        .to raise_error(described_class::MissingKeyError,
                        /ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY, ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY, ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT/)
    end

    it "passes when every key is set" do
      expect { described_class.verify!(env: all_env, credentials: no_credentials) }.not_to raise_error
    end
  end

  describe ".check_at_boot?" do
    it "checks in production" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("production"))

      expect(described_class.check_at_boot?(env: {})).to be(true)
    end

    it "skips the Docker asset build, which has no runtime env" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("production"))

      expect(described_class.check_at_boot?(env: { "SECRET_KEY_BASE_DUMMY" => "1" })).to be(false)
    end

    it "skips development and test, which have fixed keys" do
      expect(described_class.check_at_boot?(env: {})).to be(false)
    end
  end

  # Production finished the backfill, so a plain-text token must fail loudly.
  it "does not read plain-text data from encrypted columns" do
    credential = create(:oauth_credential)
    # Raw SQL: a hash update_all would encrypt the value through the attribute type.
    OauthCredential.connection.exec_update(
      "UPDATE oauth_credentials SET access_token = $1 WHERE id = $2", "seed", [ "plain-text-token", credential.id ]
    )

    expect { OauthCredential.find(credential.id).access_token }.to raise_error(ActiveRecord::Encryption::Errors::Decryption)
  end
end
