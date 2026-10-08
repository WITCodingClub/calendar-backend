# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: brightspace_syllabus_preferences
#
#  id                 :bigint           not null, primary key
#  confirmed          :jsonb            not null
#  source_revision    :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  course_offering_id :bigint           not null
#  user_id            :bigint           not null
#
# Indexes
#
#  index_brightspace_syllabus_preferences_on_course_offering_id  (course_offering_id) UNIQUE
#  index_brightspace_syllabus_preferences_on_user_id             (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (course_offering_id => brightspace_course_offerings.id)
#  fk_rails_...  (user_id => users.id)
#
RSpec.describe Brightspace::SyllabusPreference, type: :model do
  subject { create(:brightspace_syllabus_preference) }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to belong_to(:course_offering) }
  it { is_expected.to validate_uniqueness_of(:course_offering_id) }
  it { is_expected.to validate_presence_of(:source_revision) }
  it { is_expected.to validate_length_of(:source_revision).is_at_most(128) }

  # No matcher checks the JSON type or size of a jsonb column.
  it "needs an object of limited size" do
    expect(build(:brightspace_syllabus_preference, confirmed: [ 1 ])).not_to be_valid
    expect(build(:brightspace_syllabus_preference, confirmed: { "text" => "x" * 200_001 })).not_to be_valid
  end

  # A check across two associations, which no matcher covers.
  it "rejects a class of another user" do
    preference = build(:brightspace_syllabus_preference, user: create(:user))

    expect(preference).not_to be_valid
    expect(preference.errors[:course_offering]).to include("is not one of your classes")
  end
end
