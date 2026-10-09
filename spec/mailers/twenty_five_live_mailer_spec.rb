# frozen_string_literal: true

require "rails_helper"

RSpec.describe TwentyFiveLiveMailer, type: :mailer do
  describe "#constant_drift_notification" do
    subject(:mail) { described_class.constant_drift_notification(drifts) }

    let(:drifts) do
      [ { entity: "Space features", added: [ { id: 7, name: "Projector" } ], removed: [], changed: [] } ]
    end

    it "lists the drift and links to the admin page and the constants" do
      body = mail.body.to_s

      expect(body).to include("Space features").and include('id=7 "Projector"')
      expect(body).to include("Admin: http://example.com/admin")
      expect(body).to include("https://github.com/WITCodingClub/calendar-backend/tree/main/app/lib/twenty_five_live")
    end

    it "ends with the shared footer" do
      expect(mail.body.to_s).to include("--\nWIT Calendar, from the WIT Coding Club.")
    end
  end
end
