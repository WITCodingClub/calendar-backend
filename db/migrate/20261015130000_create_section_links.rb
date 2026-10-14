# frozen_string_literal: true

# Banner's own lecture and lab pairs (fetchLinkedSections). The link
# identifiers on courses do not always show the real pairs, so these rows are
# the source of truth once they are fetched. See Catalog::SectionLinksSync.
#
# option_group keeps Banner's grouping: a section can be taken with any one of
# its groups, and every section in that group is needed.
class CreateSectionLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :section_links do |t|
      # The unique index below starts with course_id, so it serves lookups by course.
      t.references :course,        null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :linked_course, null: false, foreign_key: { to_table: :courses, on_delete: :cascade }
      t.integer :option_group, null: false
      # The linked section's credit hours as Banner reports them in the pair:
      # 0 for a lab, while the courses row keeps Banner's catalog value.
      t.integer :credit_hours
      t.timestamps
    end

    add_index :section_links, [ :course_id, :option_group, :linked_course_id ], unique: true,
                                                                               name: "index_section_links_on_course_group_linked"

    # When Banner's links were last fetched for this section. Null means not yet,
    # so the old link identifier rule still applies.
    add_column :courses, :links_fetched_at, :datetime
  end
end
