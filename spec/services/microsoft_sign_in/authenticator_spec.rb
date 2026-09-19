# frozen_string_literal: true

require "rails_helper"

RSpec.describe MicrosoftSignIn::Authenticator do
  let(:email) { "authn.student@wit.edu" }
  let(:oid)   { "0c0ffee0-1111-4000-8000-000000000001" }

  before { configure_microsoft_sign_in }

  it "treats an idp claim that names the WIT tenant as a member" do
    auth = microsoft_auth_hash(email: email, oid: oid, idp: "https://sts.windows.net/#{MicrosoftSignInHelpers::TEST_TENANT_ID}/")

    result = described_class.call(auth)

    expect(result).to be_success
    expect(result.user.email).to eq(email)
  end

  it "lowercases the email before it looks up the account" do
    user = create(:user, email: email)

    result = described_class.call(microsoft_auth_hash(email: "Authn.Student@WIT.edu", oid: oid))

    expect(result.user).to eq(user)
  end

  it "finds the identity again when Microsoft sends the ids in upper case" do
    first = described_class.call(microsoft_auth_hash(email: email, oid: oid)).user

    expect { described_class.call(microsoft_auth_hash(email: email, oid: oid.upcase)) }
      .not_to change(SignInIdentity, :count)
    expect(SignInIdentity.sole).to have_attributes(user: first, uid: oid)
  end

  it "falls back to preferred_username when the email claim is empty" do
    auth = microsoft_auth_hash(email: email, oid: oid)
    auth.info.email = nil

    expect(described_class.call(auth).user.email).to eq(email)
  end

  it "refuses a token with no object id" do
    auth = microsoft_auth_hash(email: email, oid: "")

    expect(described_class.call(auth).error).to eq(described_class::WRONG_ACCOUNT)
  end

  it "refuses a guest even when an identity would otherwise be created" do
    auth = microsoft_auth_hash(email: email, oid: oid, idp: "live.com")

    expect { described_class.call(auth) }.not_to change(SignInIdentity, :count)
  end
end
