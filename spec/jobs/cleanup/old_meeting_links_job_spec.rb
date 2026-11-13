# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cleanup::OldMeetingLinksJob do
  it "deletes unused links that stopped working more than a week ago" do
    old_revoked = create(:meeting_link, :revoked, revoked_at: 8.days.ago)
    old_expired = create(:meeting_link, :expired).tap { |link| link.update_columns(expires_at: 8.days.ago) }
    new_revoked = create(:meeting_link, :revoked, revoked_at: 6.days.ago)
    active      = create(:meeting_link)
    old_used    = create(:meeting_link, :used).tap { |link| link.update_columns(expires_at: 8.days.ago) }

    described_class.perform_now

    expect(MeetingLink.all).to contain_exactly(new_revoked, active, old_used)
    expect(MeetingLink.where(id: [ old_revoked.id, old_expired.id ])).to be_empty
  end
end
