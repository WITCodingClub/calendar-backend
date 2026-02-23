# frozen_string_literal: true

# == Schema Information
#
# Table name: transfer_universities
# Database name: primary
#
#  id         :bigint           not null, primary key
#  active     :boolean          default(TRUE), not null
#  code       :string           not null
#  country    :string
#  name       :string           not null
#  state      :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_transfer_universities_on_active  (active)
#  index_transfer_universities_on_code    (code) UNIQUE
#  index_transfer_universities_on_name    (name)
#
require "rails_helper"

RSpec.describe Transfer::University do
  describe "validations" do
    subject { build(:transfer_university) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:code) }
    it { is_expected.to validate_uniqueness_of(:code) }
  end

  describe "associations" do
    it { is_expected.to have_many(:transfer_courses).class_name("Transfer::Course").dependent(:destroy) }
  end

  describe "scopes" do
    let!(:active_university) { create(:transfer_university, active: true) }
    let!(:inactive_university) { create(:transfer_university, :inactive) }
    let!(:ma_university) { create(:transfer_university, state: "MA") }
    let!(:ca_university) { create(:transfer_university, state: "CA") }
    let!(:international_university) { create(:transfer_university, :international) }

    describe ".active" do
      it "returns only active universities" do
        expect(described_class.active).to include(active_university)
        expect(described_class.active).not_to include(inactive_university)
      end
    end

    describe ".by_state" do
      it "returns universities for the specified state" do
        expect(described_class.by_state("MA")).to include(ma_university)
        expect(described_class.by_state("MA")).not_to include(ca_university)
      end
    end

    describe ".by_country" do
      it "returns universities for the specified country" do
        expect(described_class.by_country("Canada")).to include(international_university)
        expect(described_class.by_country("Canada")).not_to include(ma_university)
      end
    end
  end

  describe "#equivalencies" do
    let(:university) { create(:transfer_university) }
    let(:transfer_course) { create(:transfer_course, university: university) }
    let!(:equivalency) { create(:transfer_equivalency, transfer_course: transfer_course) }

    it "returns all equivalencies through courses" do
      expect(university.equivalencies).to include(equivalency)
    end
  end
end
