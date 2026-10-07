# frozen_string_literal: true

require "rails_helper"

RSpec.describe MeetingLinkPolicy do
  let(:owner)    { create(:user) }
  let(:stranger) { create(:user) }
  let(:link)     { create(:meeting_link, user: owner) }

  it "lets any signed-in person list and make links" do
    expect(described_class.new(stranger, MeetingLink)).to have_attributes(index?: true, create?: true)
    expect(described_class.new(nil, MeetingLink)).to have_attributes(index?: false, create?: false)
  end

  it "lets only the owner revoke a link" do
    expect(described_class.new(owner, link).destroy?).to be(true)
    expect(described_class.new(stranger, link).destroy?).to be(false)
    expect(described_class.new(nil, link).destroy?).to be(false)
  end

  describe MeetingLinkPolicy::Scope do
    it "returns only the person's own links" do
      other_link = create(:meeting_link, user: stranger)

      expect(described_class.new(owner, MeetingLink).resolve).to contain_exactly(link)
      expect(described_class.new(stranger, MeetingLink).resolve).to contain_exactly(other_link)
      expect(described_class.new(nil, MeetingLink).resolve).to be_empty
    end
  end
end
