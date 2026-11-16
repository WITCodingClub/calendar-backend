# frozen_string_literal: true

require "rails_helper"

RSpec.describe FriendMeetings::UpdateJob do
  let(:meeting)   { create(:friend_meeting) }
  let(:publisher) { instance_double(FriendMeetings::Publisher, update: nil) }

  it "writes the change to the owner's Google calendar" do
    credential = create(:oauth_credential, token_expires_at: 1.hour.from_now)
    calendar = create(:course_calendar, oauth_credential: credential, external_calendar_id: "synthetic-course-calendar")
    meeting = create(:friend_meeting, user: credential.user, destinations: %w[google])
    create(:calendar_event, :for_friend_meeting, friend_meeting: meeting, course_calendar: calendar,
                                                 external_event_id: "gcal_synthetic_meeting")
    put = stub_request(:put, "#{GoogleApiStubs::GOOGLE_CALENDAR_API}/calendars/synthetic-course-calendar/events/gcal_synthetic_meeting")
          .with(query: hash_including({}))
          .to_return(status: 200, body: file_fixture("google_calendar/event_created.json").read,
                     headers: { "Content-Type" => "application/json" })

    described_class.perform_now(meeting)

    expect(put).to have_been_requested.once
  end

  it "discards the job when the Google refresh token was revoked" do
    allow(FriendMeetings::Publisher).to receive(:new).and_return(publisher)
    allow(publisher).to receive(:update).and_raise(Google::Auth::AuthorizationError.new("synthetic invalid_grant"))

    expect { described_class.perform_now(meeting) }.not_to raise_error
  end
end
