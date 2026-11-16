# frozen_string_literal: true

require "rails_helper"

RSpec.describe MeetingLinks::Removal do
  let(:link) { create(:meeting_link) }

  describe ".permanent?" do
    it "is true only for true and 1" do
      expect(%w[true 1].map { |value| described_class.permanent?(value) }).to all(be(true))
      expect([ "yes", "", nil, "false" ].map { |value| described_class.permanent?(value) }).to all(be(false))
    end
  end

  it "revokes an active link" do
    expect(described_class.call(link, permanent: false).outcome).to eq(:revoked)
    expect(link.reload).to be_revoked
  end

  it "keeps an active link on a permanent delete" do
    expect(described_class.call(link, permanent: true).outcome).to eq(:active)
    expect(MeetingLink.exists?(link.id)).to be(true)
  end

  it "deletes a revoked link on a permanent delete" do
    link.revoke!

    expect(described_class.call(link, permanent: true).outcome).to eq(:deleted)
    expect(MeetingLink.exists?(link.id)).to be(false)
  end

  it "keeps a used link" do
    link.update_column(:used_at, Time.current)

    expect(described_class.call(link, permanent: false).outcome).to eq(:used)
    expect(described_class.call(link, permanent: true).outcome).to eq(:used)
    expect(link.reload.revoked?).to be(false)
  end

  it "gives the refusal of each outcome that changed nothing" do
    link.update_column(:used_at, Time.current)

    expect(described_class.call(link, permanent: true).refusal.code).to eq("MEETING_LINK_USED")
    expect(described_class.call(link, permanent: false).refusal.code).to be_nil
    expect(described_class::Result.new(outcome: :active, permanent: true).refusal.code).to eq("MEETING_LINK_ACTIVE")
    expect(described_class::Result.new(outcome: :revoked, permanent: false).refusal).to be_nil
  end
end
