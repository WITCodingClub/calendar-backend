# frozen_string_literal: true

require "rails_helper"

RSpec.describe FriendMeetingAttendeeRemover do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:zone)   { Time.find_zone!("America/New_York") }
  let(:user)   { create(:user) }
  let(:friend) { create(:user) }
  let(:other)  { create(:user) }

  around { |example| travel_to(zone.local(2026, 10, 7, 12)) { example.run } }

  def meeting_for(owner, *attendees, **attributes)
    meeting = create(:friend_meeting, user: owner, start_time: zone.local(2026, 10, 14, 15), end_time: zone.local(2026, 10, 14, 16), **attributes)
    attendees.each { |person| create(:friend_meeting_attendee, friend_meeting: meeting, user: person) }
    meeting
  end

  it "takes each person off the other's future meetings and updates the invited ones" do
    invited     = meeting_for(user, friend, other, invite_friends: true)
    not_invited = meeting_for(user, friend)
    theirs      = meeting_for(friend, user, invite_friends: true)

    expect { described_class.call(user.id, friend.id) }
      .to have_enqueued_job(FriendMeetingUpdateJob).with(invited)
      .and have_enqueued_job(FriendMeetingUpdateJob).with(theirs)

    expect(invited.attendees).to eq([ other ])
    expect(not_invited.attendees).to be_empty
    expect(theirs.attendees).to be_empty
    expect(enqueued_jobs.size).to eq(2)
  end

  it "takes the ex-friend off past meetings too, so they cannot read them, and updates no event there" do
    past = meeting_for(user, friend, invite_friends: true, start_time: zone.local(2026, 10, 1, 15), end_time: zone.local(2026, 10, 1, 16))

    expect { described_class.call(user.id, friend.id) }.not_to have_enqueued_job(FriendMeetingUpdateJob)

    expect(past.attendees).to be_empty
    expect(FriendMeetingPolicy::Scope.new(friend, FriendMeeting).resolve).not_to include(past)
  end

  it "leaves other people alone" do
    unrelated = meeting_for(user, other, invite_friends: true)
    strangers = meeting_for(other, friend)

    described_class.call(user.id, friend.id)

    expect(unrelated.attendees).to eq([ other ])
    expect(strangers.attendees).to eq([ friend ])
  end
end
