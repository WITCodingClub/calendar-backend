# frozen_string_literal: true

require "rails_helper"

RSpec.describe FriendMeetings::ResumeJob do
  let(:user)      { create(:user) }
  let(:publisher) { instance_double(FriendMeetings::Publisher, resume: nil) }

  it "resumes the person's meeting work" do
    allow(FriendMeetings::Publisher).to receive(:new).with(user).and_return(publisher)

    described_class.perform_now(user)

    expect(publisher).to have_received(:resume)
  end
end
