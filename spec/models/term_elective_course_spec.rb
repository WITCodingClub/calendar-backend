# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: term_elective_courses
#
#  id                    :bigint           not null, primary key
#  course_number         :integer          not null
#  heading               :text
#  position              :integer          default(0), not null
#  subject_code          :string           not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  catalog_course_id     :bigint
#  term_elective_list_id :bigint           not null
#
# Indexes
#
#  idx_term_elective_courses_unique                               (term_elective_list_id,subject_code,course_number,heading) UNIQUE NULLS NOT DISTINCT
#  index_term_elective_courses_on_catalog_course_id               (catalog_course_id)
#  index_term_elective_courses_on_subject_code_and_course_number  (subject_code,course_number)
#
# Foreign Keys
#
#  fk_rails_...  (catalog_course_id => catalog_courses.id) ON DELETE => nullify
#  fk_rails_...  (term_elective_list_id => term_elective_lists.id) ON DELETE => cascade
#
RSpec.describe TermElectiveCourse do
  subject { create(:term_elective_course) }

  it { is_expected.to belong_to(:term_elective_list) }
  it { is_expected.to belong_to(:catalog_course).optional }
  it { is_expected.to validate_presence_of(:subject_code) }
  it { is_expected.to validate_presence_of(:course_number) }
  it { is_expected.to validate_uniqueness_of(:course_number).scoped_to(:term_elective_list_id, :subject_code, :heading) }

  # The unique index treats a nil heading as one value. No matcher checks
  # the index.
  it "allows a course once with no heading in a list" do
    first = create(:term_elective_course, heading: nil)
    copy = first.dup

    expect { copy.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "links to the catalog course with its code" do
    catalog_course = create(:catalog_course, subject_code: "COMP", course_number: 2000)
    course = create(:term_elective_course, subject_code: "COMP", course_number: 2000)

    described_class.link_catalog_courses

    expect(course.reload.catalog_course).to eq(catalog_course)
  end
end
