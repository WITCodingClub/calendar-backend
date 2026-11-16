# frozen_string_literal: true

require "rails_helper"

RSpec.describe OauthCredentials::Disconnect do
  let(:user) { create(:user) }
  let!(:credential) { create(:oauth_credential, user: user) }

  it "removes a Google account when the user has another one" do
    create(:oauth_credential, user: user, email: "second@example.test")

    expect(described_class.call(credential)).to be(true)
    expect(OauthCredential.exists?(credential.id)).to be(false)
  end

  it "keeps the last Google account" do
    create(:oauth_credential, :microsoft, user: user)

    expect(described_class.call(credential)).to be(false)
    expect(OauthCredential.exists?(credential.id)).to be(true)
  end
end
