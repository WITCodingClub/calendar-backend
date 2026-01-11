# frozen_string_literal: true

# == Schema Information
#
# Table name: rating_distributions
# Database name: primary
#
#  id                       :bigint           not null, primary key
#  avg_difficulty           :decimal(3, 2)
#  avg_rating               :decimal(3, 2)
#  num_ratings              :integer          default(0)
#  r1                       :integer          default(0)
#  r2                       :integer          default(0)
#  r3                       :integer          default(0)
#  r4                       :integer          default(0)
#  r5                       :integer          default(0)
#  total                    :integer          default(0)
#  would_take_again_percent :decimal(5, 2)
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  faculty_id               :bigint           not null
#
# Indexes
#
#  index_rating_distributions_on_faculty_id  (faculty_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (faculty_id => faculties.id)
#
require "rails_helper"

RSpec.describe RatingDistribution do
  describe "validations" do
    it "is valid with valid attributes" do
      distribution = build(:rating_distribution, faculty: create(:faculty))
      expect(distribution).to be_valid
    end

    it "requires faculty to be unique" do
      faculty = create(:faculty)
      create(:rating_distribution, faculty: faculty)
      duplicate = build(:rating_distribution, faculty: faculty)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:faculty_id]).to include("has already been taken")
    end
  end

  describe "associations" do
    it "belongs to a faculty" do
      faculty = create(:faculty)
      distribution = create(:rating_distribution, faculty: faculty)
      expect(distribution.faculty).to eq(faculty)
    end
  end

  describe "#percentage" do
    let(:faculty) { create(:faculty) }

    it "calculates percentage for a given rating level" do
      distribution = create(:rating_distribution,
        faculty: faculty,
        r1: 10, r2: 20, r3: 30, r4: 25, r5: 15,
        total: 100)

      expect(distribution.percentage(1)).to eq(10.0)
      expect(distribution.percentage(2)).to eq(20.0)
      expect(distribution.percentage(3)).to eq(30.0)
      expect(distribution.percentage(4)).to eq(25.0)
      expect(distribution.percentage(5)).to eq(15.0)
    end

    it "returns 0 when total is zero" do
      distribution = build(:rating_distribution, faculty: faculty, total: 0)
      expect(distribution.percentage(1)).to eq(0)
    end

    it "rounds to two decimal places" do
      distribution = create(:rating_distribution,
        faculty: faculty,
        r1: 1, r2: 1, r3: 1, r4: 1, r5: 1,
        total: 3)

      expect(distribution.percentage(1)).to eq(33.33)
    end
  end

  describe "#percentages" do
    let(:faculty) { create(:faculty) }

    it "returns all percentages as a hash" do
      distribution = create(:rating_distribution,
        faculty: faculty,
        r1: 10, r2: 20, r3: 30, r4: 25, r5: 15,
        total: 100)

      expect(distribution.percentages).to eq({
        r1: 10.0,
        r2: 20.0,
        r3: 30.0,
        r4: 25.0,
        r5: 15.0
      })
    end

    it "returns all zeros when total is zero" do
      distribution = build(:rating_distribution,
        faculty: faculty,
        r1: 0, r2: 0, r3: 0, r4: 0, r5: 0,
        total: 0)

      expect(distribution.percentages).to eq({
        r1: 0,
        r2: 0,
        r3: 0,
        r4: 0,
        r5: 0
      })
    end
  end

  describe "public_id" do
    it "generates a public_id with rdi prefix" do
      distribution = create(:rating_distribution, faculty: create(:faculty))
      expect(distribution.public_id).to start_with("rdi_")
    end
  end
end
