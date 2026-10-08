# frozen_string_literal: true

require "rails_helper"

RSpec.describe FriendMeetingPublication do
  describe "associations and validations" do
    subject { create(:friend_meeting_publication) }

    it { is_expected.to belong_to(:friend_meeting) }
    it { is_expected.to validate_uniqueness_of(:provider).scoped_to(:friend_meeting_id).ignoring_case_sensitivity }

    it do
      expect(subject).to define_enum_for(:provider).with_values(google: "google", microsoft: "microsoft", ics: "ics")
                                                   .backed_by_column_of_type(:string).with_prefix.validating
    end

    it do
      expect(subject).to define_enum_for(:status).with_values(queued: "queued", published: "published", failed: "failed", removed: "removed")
                                                 .backed_by_column_of_type(:string).validating
    end
  end

  describe "#invitation_status" do
    it "is not_requested for a place that does not send the invitations" do
      expect(build(:friend_meeting_publication).invitation_status).to eq("not_requested")
    end

    it "follows the publication until the invitations are sent" do
      publication = create(:friend_meeting_publication, :sends_invitations)
      expect(publication.invitation_status).to eq("queued")

      publication.mark_failed!(StandardError.new("synthetic"))
      expect(publication.invitation_status).to eq("failed")

      publication.mark_published!(invitations_sent: true)
      expect(publication).to have_attributes(invitation_status: "sent", status: "published", last_error: nil)

      publication.mark_removed!
      expect(publication).to have_attributes(invitation_status: "cancelled", status: "removed", invitations_sent_at: nil)
    end
  end
end
