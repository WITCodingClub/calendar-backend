# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: elective_group_courses
#
#  id                :bigint           not null, primary key
#  course_number     :integer          not null
#  position          :integer          default(0), not null
#  requires_approval :boolean          default(FALSE), not null
#  subject_code      :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  catalog_course_id :bigint
#  elective_group_id :bigint           not null
#
# Indexes
#
#  idx_elective_group_courses_unique                               (elective_group_id,subject_code,course_number) UNIQUE
#  index_elective_group_courses_on_catalog_course_id               (catalog_course_id)
#  index_elective_group_courses_on_subject_code_and_course_number  (subject_code,course_number)
#
# Foreign Keys
#
#  fk_rails_...  (catalog_course_id => catalog_courses.id) ON DELETE => nullify
#  fk_rails_...  (elective_group_id => elective_groups.id) ON DELETE => cascade
#
RSpec.describe ElectiveGroupCourse do
  subject { create(:elective_group_course) }

  it { is_expected.to belong_to(:elective_group) }
  it { is_expected.to belong_to(:catalog_course).optional }
  it { is_expected.to validate_presence_of(:subject_code) }
  it { is_expected.to validate_presence_of(:course_number) }
  it { is_expected.to validate_uniqueness_of(:course_number).scoped_to(:elective_group_id, :subject_code) }

  it "links to the Banner course with its code" do
    course = create(:catalog_course, subject_code: "MATH", course_number: 2300)
    row = create(:elective_group_course, subject_code: "math", course_number: 2300)

    described_class.link_catalog_courses

    expect(row.reload.catalog_course).to eq(course)
  end
end
