# frozen_string_literal: true

# A Brightspace class, which the API calls a "class". It can link to a
# registration course from the user's enrollments, but it does not need one.
# data_version goes up each time the imported data of the class changes.
# == Schema Information
#
# Table name: brightspace_course_offerings
#
#  id             :bigint           not null, primary key
#  data_version   :integer          default(1), not null
#  reported_total :jsonb
#  sections       :jsonb            not null
#  title          :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  connection_id  :bigint           not null
#  course_id      :bigint
#  source_id      :string           not null
#  term_id        :bigint
#
# Indexes
#
#  idx_on_connection_id_source_id_cec08f631c            (connection_id,source_id) UNIQUE
#  index_brightspace_course_offerings_on_connection_id  (connection_id)
#  index_brightspace_course_offerings_on_course_id      (course_id)
#  index_brightspace_course_offerings_on_term_id        (term_id)
#
# Foreign Keys
#
#  fk_rails_...  (connection_id => brightspace_connections.id)
#  fk_rails_...  (course_id => courses.id)
#  fk_rails_...  (term_id => terms.id)
#
module Brightspace
  class CourseOffering < ApplicationRecord
    include EncodedIds::HashidIdentifiable

    set_public_id_prefix :bcl, min_hash_length: 12

    belongs_to :connection, class_name: "Brightspace::Connection", inverse_of: :course_offerings
    belongs_to :course, optional: true
    belongs_to :term, optional: true
    has_one :user, through: :connection

    with_options foreign_key: :course_offering_id, dependent: :destroy, inverse_of: :course_offering do
      has_many :assignments,      class_name: "Brightspace::Assignment"
      has_many :announcements,    class_name: "Brightspace::Announcement"
      has_many :grade_categories, class_name: "Brightspace::GradeCategory"
      has_many :grade_items,      class_name: "Brightspace::GradeItem"
      has_one  :syllabus,         class_name: "Brightspace::Syllabus"
    end

    validates :source_id, presence: true, length: { maximum: 64 }, uniqueness: { scope: :connection_id }
    validates :title, presence: true, length: { maximum: 500 }
    validates :data_version, numericality: { only_integer: true, greater_than: 0 }

    scope :for_user, ->(user) { joins(:connection).where(brightspace_connections: { user_id: user.id }) }

    # An opaque token for cache checks. Callers compare it, never parse it.
    def version
      "#{hashid}.#{data_version}"
    end

    # Raises the version in SQL, so two writers never lose a raise.
    def bump_version!
      self.class.where(id: id).update_all("data_version = data_version + 1, updated_at = NOW()") # rubocop:disable Rails/SkipsModelValidations
      reload
    end

    def section_state(section)
      sections.fetch(section.to_s, {})
    end
  end
end
