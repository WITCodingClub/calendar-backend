# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cleanup::UnusedOauthClientsJob do
  include ActiveSupport::Testing::TimeHelpers

  it "deletes registered clients that got no token in a day" do
    old_unused   = create(:oauth_application, :dynamic, created_at: 2.days.ago)
    old_used     = create(:oauth_application, :dynamic, created_at: 2.days.ago)
    old_revoked  = create(:oauth_application, :dynamic, created_at: 2.days.ago)
    new_unused   = create(:oauth_application, :dynamic)
    preregistered = create(:oauth_application, created_at: 2.days.ago)
    create(:oauth_access_token, application: old_used)
    create(:oauth_access_token, :revoked, application: old_revoked)

    described_class.perform_now

    expect(Doorkeeper::Application.all).to contain_exactly(old_used, new_unused, preregistered)
    expect(Doorkeeper::AccessToken.where(application_id: old_revoked.id)).to be_empty
    expect(Doorkeeper::Application.exists?(old_unused.id)).to be(false)
  end
end
