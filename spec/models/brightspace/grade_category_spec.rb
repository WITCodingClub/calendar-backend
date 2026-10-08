# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: brightspace_grade_categories
#
#  id                 :bigint           not null, primary key
#  drop_highest       :integer
#  drop_lowest        :integer
#  extra_credit       :boolean
#  name               :string           not null
#  removed_at         :datetime
#  weight             :decimal(8, 4)
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  course_offering_id :bigint           not null
#  source_id          :string           not null
#
# Indexes
#
#  index_brightspace_grade_categories_on_course_offering_id  (course_offering_id)
#  index_brightspace_grade_categories_on_source              (course_offering_id,source_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (course_offering_id => brightspace_course_offerings.id)
#
RSpec.describe Brightspace::GradeCategory, type: :model do
  subject { create(:brightspace_grade_category) }

  it { is_expected.to belong_to(:course_offering) }
  it { is_expected.to have_many(:grade_items).dependent(:nullify) }
  it { is_expected.to validate_presence_of(:source_id) }
  it { is_expected.to validate_length_of(:source_id).is_at_most(64) }
  it { is_expected.to validate_uniqueness_of(:source_id).scoped_to(:course_offering_id).ignoring_case_sensitivity }
  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_length_of(:name).is_at_most(500) }
  it { is_expected.to validate_numericality_of(:weight).is_greater_than_or_equal_to(0).allow_nil }
  it { is_expected.to validate_numericality_of(:drop_lowest).only_integer.is_greater_than_or_equal_to(0).allow_nil }
  it { is_expected.to validate_numericality_of(:drop_highest).only_integer.is_greater_than_or_equal_to(0).allow_nil }
end
