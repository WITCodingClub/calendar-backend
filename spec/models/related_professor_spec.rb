# frozen_string_literal: true

# == Schema Information
#
# Table name: related_professors
# Database name: primary
#
#  id                 :bigint           not null, primary key
#  avg_rating         :decimal(3, 2)
#  first_name         :string
#  last_name          :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  faculty_id         :bigint           not null
#  related_faculty_id :bigint
#  rmp_id             :string           not null
#
# Indexes
#
#  index_related_professors_on_faculty_id             (faculty_id)
#  index_related_professors_on_faculty_id_and_rmp_id  (faculty_id,rmp_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (faculty_id => faculties.id)
#  fk_rails_...  (related_faculty_id => faculties.id)
#
require "rails_helper"

RSpec.describe RelatedProfessor do
  describe "validations" do
    it "is valid with valid attributes" do
      related = build(:related_professor, faculty: create(:faculty), rmp_id: "rmp123")
      expect(related).to be_valid
    end

    it "requires rmp_id to be present" do
      related = build(:related_professor, faculty: create(:faculty), rmp_id: nil)
      expect(related).not_to be_valid
      expect(related.errors[:rmp_id]).to include("can't be blank")
    end

    it "requires rmp_id to be unique per faculty" do
      faculty = create(:faculty)
      create(:related_professor, faculty: faculty, rmp_id: "rmp123")
      duplicate = build(:related_professor, faculty: faculty, rmp_id: "rmp123")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:rmp_id]).to include("has already been taken")
    end

    it "allows same rmp_id for different faculties" do
      faculty1 = create(:faculty)
      faculty2 = create(:faculty)
      create(:related_professor, faculty: faculty1, rmp_id: "rmp123")
      related = build(:related_professor, faculty: faculty2, rmp_id: "rmp123")
      expect(related).to be_valid
    end
  end

  describe "associations" do
    it "belongs to a faculty" do
      faculty = create(:faculty)
      related = create(:related_professor, faculty: faculty, rmp_id: "rmp123")
      expect(related.faculty).to eq(faculty)
    end

    it "can belong to a related_faculty" do
      faculty = create(:faculty)
      related_faculty = create(:faculty)
      related = create(:related_professor,
        faculty: faculty,
        related_faculty: related_faculty,
        rmp_id: "rmp123")
      expect(related.related_faculty).to eq(related_faculty)
    end

    it "allows nil related_faculty" do
      related = build(:related_professor, faculty: create(:faculty), related_faculty: nil, rmp_id: "rmp123")
      expect(related).to be_valid
    end
  end

  describe "#try_match_faculty!" do
    let(:faculty) { create(:faculty) }

    it "matches related_faculty when a faculty with same rmp_id exists" do
      matched_faculty = create(:faculty, rmp_id: "match123")
      related = create(:related_professor, faculty: faculty, rmp_id: "match123", related_faculty: nil)

      related.try_match_faculty!

      expect(related.reload.related_faculty).to eq(matched_faculty)
    end

    it "does nothing when no matching faculty exists" do
      related = create(:related_professor, faculty: faculty, rmp_id: "nomatch123", related_faculty: nil)

      related.try_match_faculty!

      expect(related.reload.related_faculty).to be_nil
    end

    it "does nothing when related_faculty is already set" do
      existing_related = create(:faculty)
      matched_faculty = create(:faculty, rmp_id: "match123")
      related = create(:related_professor,
        faculty: faculty,
        rmp_id: "match123",
        related_faculty: existing_related)

      related.try_match_faculty!

      expect(related.reload.related_faculty).to eq(existing_related)
    end
  end

  describe "#full_name" do
    it "combines first_name and last_name" do
      related = build(:related_professor,
        faculty: create(:faculty),
        first_name: "John",
        last_name: "Smith",
        rmp_id: "rmp123")
      expect(related.full_name).to eq("John Smith")
    end
  end

  describe "public_id" do
    it "generates a public_id with rpr prefix" do
      related = create(:related_professor, faculty: create(:faculty), rmp_id: "rmp123")
      expect(related.public_id).to start_with("rpr_")
    end
  end
end
