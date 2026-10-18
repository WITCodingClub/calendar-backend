# frozen_string_literal: true

# == Schema Information
#
# Table name: section_links
#
#  id               :bigint           not null, primary key
#  credit_hours     :integer
#  option_group     :integer          not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  course_id        :bigint           not null
#  linked_course_id :bigint           not null
#
# Indexes
#
#  index_section_links_on_course_group_linked  (course_id,option_group,linked_course_id) UNIQUE
#  index_section_links_on_linked_course_id     (linked_course_id)
#
# Foreign Keys
#
#  fk_rails_...  (course_id => courses.id) ON DELETE => cascade
#  fk_rails_...  (linked_course_id => courses.id) ON DELETE => cascade
#
FactoryBot.define do
  factory :section_link do
    course
    linked_course { association :course, term: course.term }
    option_group { 0 }
    credit_hours { 0 }
  end
end
