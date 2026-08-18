# frozen_string_literal: true

class AddLinkIdentifierToCourses < ActiveRecord::Migration[8.1]
  def change
    # Banner's linkIdentifier says which sections must be registered together.
    # It reads as <slot><key>: the first character is the slot (A for the
    # lecture, B for the lab), and the rest is the key that pairs them. A
    # lecture "A1" goes with every lab "B1" of the same course.
    add_column :courses, :link_identifier,   :string
    add_column :courses, :is_section_linked, :boolean, default: false, null: false

    # Finding a section's partners means looking up the same course and key.
    add_index :courses, [ :term_id, :subject, :course_number, :link_identifier ],
              name: "index_courses_on_course_and_link_identifier"
  end
end
