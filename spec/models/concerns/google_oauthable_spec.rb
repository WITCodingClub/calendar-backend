# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleOauthable do
  let(:user) { create(:user) }

  describe "#google_credential" do
    it "gives the first Google account the person linked" do
      first = create(:oauth_credential, user: user, created_at: 2.days.ago)
      create(:oauth_credential, user: user, email: "second@example.test", created_at: 1.day.ago)
      create(:oauth_credential, :microsoft, user: user, created_at: 3.days.ago)

      expect(user.google_credential).to eq(first)
    end

    it "reads a credential that was linked after an earlier call" do
      expect(user.google_credential).to be_nil

      credential = create(:oauth_credential, user: user)

      expect(user.google_credential).to eq(credential)
    end
  end
end
