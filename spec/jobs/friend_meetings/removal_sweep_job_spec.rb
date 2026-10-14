# frozen_string_literal: true

require "rails_helper"

RSpec.describe FriendMeetings::RemovalSweepJob do
  include ActiveJob::TestHelper

  it "starts the remove job again for each meeting cancelled over an hour ago" do
    stale    = create(:friend_meeting, cancelled_at: 2.hours.ago)
    recent   = create(:friend_meeting, cancelled_at: 5.minutes.ago)
    live     = create(:friend_meeting)
    refused  = create(:friend_meeting, cancelled_at: 2.hours.ago, destinations: %w[google])
    refused.publication_for("google").mark_failed!("MicrosoftGraph::AuthError")

    described_class.perform_now

    expect(FriendMeetings::RemoveJob).to have_been_enqueued.with(stale).once
    [ recent, live, refused ].each { |meeting| expect(FriendMeetings::RemoveJob).not_to have_been_enqueued.with(meeting) }
  end

  # A revoked Google refresh token raises Google::Auth::AuthorizationError from
  # the token refresh, not Google::Apis::AuthorizationError from an API call.
  it "does not start the remove job again for a meeting whose Google refresh token was revoked" do
    credential = create(:oauth_credential, refresh_token: "synthetic-refresh", token_expires_at: 1.minute.ago)
    calendar   = create(:course_calendar, oauth_credential: credential, external_calendar_id: "synthetic-course-calendar")
    meeting    = create(:friend_meeting, :cancelled, user: credential.user, destinations: %w[google])
    create(:calendar_event, :for_friend_meeting, friend_meeting: meeting, course_calendar: calendar)
    stub_request(:post, "https://oauth2.googleapis.com/token")
      .to_return(status: 400, body: { error: "invalid_grant", error_description: "Token has been expired or revoked." }.to_json,
                 headers: { "Content-Type" => "application/json" })
    meeting.update!(cancelled_at: 2.hours.ago)

    expect { FriendMeetings::RemoveJob.perform_now(meeting) }.not_to raise_error
    expect(meeting.publication_for("google")).to have_attributes(status: "failed")

    expect { described_class.perform_now }.not_to have_enqueued_job(FriendMeetings::RemoveJob)
  end

  it "runs every hour in production" do
    schedule = YAML.load_file(Rails.root.join("config/recurring.yml")).dig("production", "friend_meeting_removal_sweep")

    expect(schedule).to include("class" => "FriendMeetings::RemovalSweepJob", "schedule" => "every hour at minute 27")
  end
end
