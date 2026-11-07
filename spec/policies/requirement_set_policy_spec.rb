# frozen_string_literal: true

require "rails_helper"

RSpec.describe RequirementSetPolicy do
  let(:record) { build(:requirement_set) }

  %i[index? show? review?].each do |query|
    describe "##{query}" do
      it "permits an admin" do
        expect(described_class.new(build(:user, access_level: :admin), record).public_send(query)).to be(true)
      end

      it "refuses a user without admin access" do
        expect(described_class.new(build(:user), record).public_send(query)).to be_falsey
      end

      it "refuses a guest" do
        expect(described_class.new(nil, record).public_send(query)).to be_falsey
      end
    end
  end
end
