# frozen_string_literal: true

require "rails_helper"

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
RSpec.describe SectionLink do
  it { is_expected.to belong_to(:course) }
  it { is_expected.to belong_to(:linked_course).class_name("Course") }
  it { is_expected.to validate_presence_of(:option_group) }
  it { is_expected.to validate_numericality_of(:option_group).only_integer.is_greater_than_or_equal_to(0) }
end
