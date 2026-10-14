# frozen_string_literal: true

# One partner section from Banner's fetchLinkedSections for a section. The rows
# with the same option_group form one set that must be taken together; a
# section can be taken with any one of its sets. Catalog::SectionLinksSync
# writes them.
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
class SectionLink < ApplicationRecord
  belongs_to :course
  belongs_to :linked_course, class_name: "Course"

  validates :option_group, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
