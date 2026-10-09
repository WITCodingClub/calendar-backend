# frozen_string_literal: true

require "rails_helper"

RSpec.describe MeetingLinkMailer, type: :mailer do
  let(:zone)    { Time.zone }
  let(:owner)   { create(:user, email: "owner@wit.edu", first_name: "Sample", last_name: "Owner") }
  let(:meeting) do
    create(:friend_meeting, user: owner, title: "Project check-in", guest_name: "Sample Guest", guest_email: "guest@example.com",
                            start_time: zone.local(2026, 10, 8, 10), end_time: zone.local(2026, 10, 8, 10, 30))
  end
  let(:link) { create(:meeting_link, :used, user: owner, friend_meeting: meeting) }

  describe "#booked" do
    subject(:mail) { described_class.booked(link) }

    it "goes to the guest, with replies to the owner" do
      expect(mail.to).to eq([ "guest@example.com" ])
      expect(mail.reply_to).to eq([ "owner@wit.edu" ])
      expect(mail.subject).to eq("Your meeting with Sample Owner is booked")
    end

    it "gives the title, the date, and the time in both parts" do
      [ mail.html_part.body.to_s, mail.text_part.body.to_s ].each do |body|
        expect(body).to include("Hi Sample Guest").and include("Project check-in")
        expect(body).to include("Thursday, October 8, 2026").and include("10:00 AM to 10:30 AM EDT")
      end
    end

    it "has no email settings link, because the guest has no account" do
      expect(mail.html_part.body.to_s).not_to include("Change which emails you get")
      expect(mail.text_part.body.to_s).not_to include("Change which emails you get")
    end

    it "says that no calendar invitation comes when the owner uses only the ICS feed" do
      expect(mail.text_part.body.to_s).to include("You will not get a separate calendar invitation.")
    end

    it "says that an invitation also comes when the owner has a provider calendar" do
      credential = create(:oauth_credential, user: owner)
      create(:course_calendar, oauth_credential: credential)

      expect(mail.text_part.body.to_s).to include("You will also get a calendar invitation")
    end
  end
end
