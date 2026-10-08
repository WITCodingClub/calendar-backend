# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: brightspace_syllabi
#
#  id                 :bigint           not null, primary key
#  extracted          :jsonb            not null
#  removed_at         :datetime
#  revision           :string           not null
#  source_url         :string
#  title              :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  course_offering_id :bigint           not null
#  source_id          :string
#
# Indexes
#
#  index_brightspace_syllabi_on_course_offering_id  (course_offering_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (course_offering_id => brightspace_course_offerings.id)
#
RSpec.describe Brightspace::Syllabus, type: :model do
  subject { create(:brightspace_syllabus) }

  it { is_expected.to belong_to(:course_offering) }
  it { is_expected.to validate_uniqueness_of(:course_offering_id) }
  it { is_expected.to validate_presence_of(:revision) }
  it { is_expected.to validate_length_of(:revision).is_at_most(128) }
  it { is_expected.to validate_length_of(:title).is_at_most(500) }

  # A custom validation: no matcher checks the JSON type of a jsonb column.
  it "rejects extracted data that is not an object" do
    syllabus = build(:brightspace_syllabus, extracted: [ "rule" ])

    expect(syllabus).not_to be_valid
    expect(syllabus.errors[:extracted]).to include("must be an object")
  end
end
