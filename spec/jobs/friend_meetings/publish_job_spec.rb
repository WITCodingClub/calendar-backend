# frozen_string_literal: true

require "rails_helper"

RSpec.describe FriendMeetings::PublishJob do
  let(:meeting)   { create(:friend_meeting) }
  let(:publisher) { instance_double(FriendMeetings::Publisher, publish: nil) }

  it "discards the job when the Google refresh token was revoked" do
    allow(FriendMeetings::Publisher).to receive(:new).and_return(publisher)
    allow(publisher).to receive(:publish).and_raise(Google::Auth::AuthorizationError.new("synthetic invalid_grant"))

    expect { described_class.perform_now(meeting) }.not_to raise_error
  end
end
