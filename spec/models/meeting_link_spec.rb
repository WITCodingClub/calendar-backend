# frozen_string_literal: true

require "rails_helper"

RSpec.describe MeetingLink do
  include ActiveSupport::Testing::TimeHelpers

  let(:zone) { Time.zone }

  around { |example| travel_to(zone.local(2026, 10, 7, 12)) { example.run } }

  describe "associations and validations" do
    subject { create(:meeting_link) }

    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:friend_meeting).optional }
    it { is_expected.to belong_to(:guest_user).class_name("User").optional }
    it { is_expected.to validate_presence_of(:starts_on) }
    it { is_expected.to validate_presence_of(:ends_on) }
    it { is_expected.to validate_inclusion_of(:duration_minutes).in_array(MeetingLink::DURATIONS) }
    it { is_expected.to validate_length_of(:title).is_at_most(MeetingLink::TITLE_MAX_LENGTH) }
    it { is_expected.to validate_uniqueness_of(:token_digest) }
  end

  describe "the token" do
    it "keeps the raw token only on the new instance and stores its SHA-256 digest" do
      link = create(:meeting_link)

      expect(link.token).to be_present
      expect(link.token_digest).to eq(OpenSSL::Digest::SHA256.hexdigest(link.token))
      expect(described_class.find(link.id).token).to be_nil
      expect(described_class.column_names).not_to include("token")
    end

    it "finds the link by its raw token, and finds nothing for a wrong or blank token" do
      link = create(:meeting_link)

      expect(described_class.find_by_token(link.token)).to eq(link)
      expect(described_class.find_by_token("#{link.token}x")).to be_nil
      expect(described_class.find_by_token("")).to be_nil
    end

    it "gives a URL only on the instance that knows the token" do
      link = create(:meeting_link)

      expect(link.url).to eq("http://example.com/meet/#{link.token}")
      expect(described_class.find(link.id).url).to be_nil
    end
  end

  it "expires at the end of the last day when no expiry is given" do
    link = create(:meeting_link, starts_on: Date.new(2026, 10, 8), ends_on: Date.new(2026, 10, 9))

    expect(link.expires_at).to be_within(1.second).of(zone.local(2026, 10, 9).end_of_day)
  end

  # These compare a column with today, with another column, or with other
  # rows, which no shoulda matcher covers.
  describe "create validations" do
    it "refuses a start date in the past" do
      link = build(:meeting_link, starts_on: Date.new(2026, 10, 6))

      expect(link).not_to be_valid
      expect(link.errors[:starts_on]).to include("must be today or later")
    end

    it "refuses an end date before the start date" do
      link = build(:meeting_link, starts_on: Date.new(2026, 10, 9), ends_on: Date.new(2026, 10, 8))

      expect(link).not_to be_valid
      expect(link.errors[:ends_on]).to include("must be on or after the start date")
    end

    it "refuses a range longer than the limit" do
      link = build(:meeting_link, starts_on: Date.new(2026, 10, 8), ends_on: Date.new(2026, 10, 8) + MeetingLink::MAX_RANGE_DAYS)

      expect(link).not_to be_valid
      expect(link.errors[:ends_on].first).to start_with("must be no more than")
    end

    it "refuses an expiry in the past or too far away" do
      expect(build(:meeting_link, expires_at: 1.minute.ago)).not_to be_valid
      expect(build(:meeting_link, expires_at: MeetingLink::MAX_EXPIRY.from_now + 1.minute)).not_to be_valid
      expect(build(:meeting_link, expires_at: 2.days.from_now)).to be_valid
    end

    it "refuses a new link when the person already has the most active links" do
      user = create(:user)
      create_list(:meeting_link, MeetingLink::MAX_ACTIVE_LINKS, user: user)

      link = build(:meeting_link, user: user)
      expect(link).not_to be_valid
      expect(link.errors[:base].first).to include("no more than #{MeetingLink::MAX_ACTIVE_LINKS} active meeting links")
    end
  end

  describe "#usable? and #status" do
    it "is active and usable when new" do
      link = create(:meeting_link)

      expect(link).to be_usable
      expect(link.status).to eq("active")
    end

    it "is not usable once used, revoked, or expired" do
      used    = create(:meeting_link, :used)
      revoked = create(:meeting_link, :revoked)
      expired = create(:meeting_link, :expired)

      expect([ used, revoked, expired ].map(&:usable?)).to eq([ false, false, false ])
      expect([ used, revoked, expired ].map(&:status)).to eq(%w[used revoked expired])
      expect(described_class.usable).to be_empty
    end
  end

  describe "#revoke!" do
    it "sets revoked_at once" do
      link = create(:meeting_link)
      link.revoke!
      first = link.revoked_at

      travel 1.hour
      link.revoke!
      expect(link.reload.revoked_at).to eq(first)
    end
  end

  describe "#meeting_title" do
    it "uses the owner's title, or names the guest" do
      expect(build(:meeting_link, title: "Project check-in").meeting_title("Sample Guest")).to eq("Project check-in")
      expect(build(:meeting_link).meeting_title("Sample Guest")).to eq("Meeting with Sample Guest")
    end
  end
end
