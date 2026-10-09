# frozen_string_literal: true

require "rails_helper"

RSpec.describe ServiceAccountPolicy do
  describe "#manage?" do
    it "permits an owner" do
      expect(described_class.new(build(:user, access_level: :owner), :service_account).manage?).to be(true)
    end

    it "refuses a super admin" do
      expect(described_class.new(build(:user, access_level: :super_admin), :service_account).manage?).to be_falsey
    end

    it "refuses an admin" do
      expect(described_class.new(build(:user, access_level: :admin), :service_account).manage?).to be_falsey
    end

    it "refuses a guest" do
      expect(described_class.new(nil, :service_account).manage?).to be_falsey
    end
  end
end
