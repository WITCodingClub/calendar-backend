# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GET /calendar/:calendar_token friend meetings", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:zone)   { Time.find_zone!("America/New_York") }
  let(:user)   { create(:user) }
  let(:friend) { create(:user, first_name: "Sample", last_name: "Friend", email: "sample.friend@wit.edu") }

  around { |example| travel_to(zone.local(2026, 10, 7, 12)) { example.run } }

  def feed_events
    get "/calendar/#{user.calendar_token}"
    expect(response).to have_http_status(:ok)
    Icalendar::Calendar.parse(response.body).first.events
  end

  def meeting_with_friend(**attributes)
    meeting = create(:friend_meeting, user: user, title: "Synthetic Study Group",
                                      start_time: zone.local(2026, 10, 13, 15), end_time: zone.local(2026, 10, 13, 16), **attributes)
    create(:friend_meeting_attendee, friend_meeting: meeting, user: friend)
    meeting
  end

  it "shows a weekly meeting with its weekly rule" do
    meeting = meeting_with_friend(location: "Synthetic Library", frequency: "weekly", term: create(:term), repeat_until: Date.new(2026, 12, 18))

    event = feed_events.find { |e| e.uid == "friend-meeting-#{meeting.public_id}@calendar-util.wit.edu" }

    expect(event.summary).to eq("Synthetic Study Group")
    expect(event.location).to eq("Synthetic Library")
    expect(event.dtstart).to eq(zone.local(2026, 10, 13, 15))
    expect(event.rrule.first).to have_attributes(frequency: "WEEKLY", by_day: [ "TU" ], until: "20261219T045959Z")
    expect(event.attendee).to be_empty
  end

  it "lists the friends as attendees when the person asked to invite them" do
    meeting_with_friend(invite_friends: true)

    attendee = feed_events.sole.attendee.sole

    expect(attendee.to_s).to eq("mailto:sample.friend@wit.edu")
    expect(attendee.ical_params["cn"]).to eq([ "Sample Friend" ])
  end

  it "leaves out a meeting that has ended" do
    create(:friend_meeting, user: user, start_time: zone.local(2026, 10, 1, 15), end_time: zone.local(2026, 10, 1, 16))

    expect(feed_events).to be_empty
  end
end
