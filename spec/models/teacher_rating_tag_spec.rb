# frozen_string_literal: true

# == Schema Information
#
# Table name: teacher_rating_tags
# Database name: primary
#
#  id            :bigint           not null, primary key
#  tag_count     :integer          default(0)
#  tag_name      :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  faculty_id    :bigint           not null
#  rmp_legacy_id :integer          not null
#
# Indexes
#
#  index_teacher_rating_tags_on_faculty_id                    (faculty_id)
#  index_teacher_rating_tags_on_faculty_id_and_rmp_legacy_id  (faculty_id,rmp_legacy_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (faculty_id => faculties.id)
#
require "rails_helper"

RSpec.describe TeacherRatingTag do
  describe "validations" do
    it "is valid with valid attributes" do
      tag = build(:teacher_rating_tag, faculty: create(:faculty), rmp_legacy_id: 1, tag_name: "Helpful")
      expect(tag).to be_valid
    end

    it "requires rmp_legacy_id to be present" do
      tag = build(:teacher_rating_tag, faculty: create(:faculty), rmp_legacy_id: nil)
      expect(tag).not_to be_valid
      expect(tag.errors[:rmp_legacy_id]).to include("can't be blank")
    end

    it "requires rmp_legacy_id to be unique per faculty" do
      faculty = create(:faculty)
      create(:teacher_rating_tag, faculty: faculty, rmp_legacy_id: 1)
      duplicate = build(:teacher_rating_tag, faculty: faculty, rmp_legacy_id: 1)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:rmp_legacy_id]).to include("has already been taken")
    end

    it "allows same rmp_legacy_id for different faculties" do
      faculty1 = create(:faculty)
      faculty2 = create(:faculty)
      create(:teacher_rating_tag, faculty: faculty1, rmp_legacy_id: 1)
      tag = build(:teacher_rating_tag, faculty: faculty2, rmp_legacy_id: 1)
      expect(tag).to be_valid
    end

    it "requires tag_name to be present" do
      tag = build(:teacher_rating_tag, faculty: create(:faculty), tag_name: nil)
      expect(tag).not_to be_valid
      expect(tag.errors[:tag_name]).to include("can't be blank")
    end

    it "requires tag_count to be >= 0" do
      tag = build(:teacher_rating_tag, faculty: create(:faculty), tag_count: -1)
      expect(tag).not_to be_valid
      expect(tag.errors[:tag_count]).to include("must be greater than or equal to 0")
    end

    it "allows tag_count of 0" do
      tag = build(:teacher_rating_tag, faculty: create(:faculty), tag_count: 0)
      expect(tag).to be_valid
    end
  end

  describe "associations" do
    it "belongs to a faculty" do
      faculty = create(:faculty)
      tag = create(:teacher_rating_tag, faculty: faculty, rmp_legacy_id: 1)
      expect(tag.faculty).to eq(faculty)
    end
  end

  describe "scopes" do
    describe ".ordered_by_count" do
      it "orders by tag_count descending" do
        faculty = create(:faculty)
        low = create(:teacher_rating_tag, faculty: faculty, rmp_legacy_id: 1, tag_count: 5)
        high = create(:teacher_rating_tag, faculty: faculty, rmp_legacy_id: 2, tag_count: 20)
        mid = create(:teacher_rating_tag, faculty: faculty, rmp_legacy_id: 3, tag_count: 10)

        expect(described_class.ordered_by_count).to eq([high, mid, low])
      end
    end

    describe ".top_tags" do
      it "returns top N tags ordered by count" do
        faculty = create(:faculty)
        create(:teacher_rating_tag, faculty: faculty, rmp_legacy_id: 1, tag_count: 5)
        top1 = create(:teacher_rating_tag, faculty: faculty, rmp_legacy_id: 2, tag_count: 20)
        top2 = create(:teacher_rating_tag, faculty: faculty, rmp_legacy_id: 3, tag_count: 15)
        create(:teacher_rating_tag, faculty: faculty, rmp_legacy_id: 4, tag_count: 3)
        top3 = create(:teacher_rating_tag, faculty: faculty, rmp_legacy_id: 5, tag_count: 10)

        expect(described_class.top_tags(3)).to eq([top1, top2, top3])
      end

      it "defaults to 5 tags" do
        faculty = create(:faculty)
        6.times do |i|
          create(:teacher_rating_tag, faculty: faculty, rmp_legacy_id: i + 1, tag_count: i)
        end

        expect(described_class.top_tags.count).to eq(5)
      end
    end
  end

  describe "public_id" do
    it "generates a public_id with trt prefix" do
      tag = create(:teacher_rating_tag, faculty: create(:faculty), rmp_legacy_id: 1)
      expect(tag.public_id).to start_with("trt_")
    end
  end
end
