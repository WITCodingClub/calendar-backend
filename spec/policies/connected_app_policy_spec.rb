# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConnectedAppPolicy do
  let(:user) { create(:user) }

  it "lets a user disconnect an app that holds their token" do
    token = create(:oauth_access_token, resource_owner_id: user.id)

    expect(described_class.new(user, token.application).destroy?).to be(true)
  end

  it "refuses an app that holds only another user's token" do
    token = create(:oauth_access_token)

    expect(described_class.new(user, token.application).destroy?).to be(false)
  end

  it "refuses an app whose token for the user is revoked" do
    token = create(:oauth_access_token, :revoked, resource_owner_id: user.id)

    expect(described_class.new(user, token.application).destroy?).to be(false)
  end

  it "refuses a guest" do
    expect(described_class.new(nil, create(:oauth_application)).destroy?).to be(false)
  end
end
