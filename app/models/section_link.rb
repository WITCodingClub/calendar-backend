# frozen_string_literal: true

# One partner section from Banner's fetchLinkedSections for a section. The rows
# with the same option_group form one set that must be taken together; a
# section can be taken with any one of its sets. Catalog::SectionLinksSync
# writes them.
class SectionLink < ApplicationRecord
  belongs_to :course
  belongs_to :linked_course, class_name: "Course"

  validates :option_group, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
