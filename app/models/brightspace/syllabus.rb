# frozen_string_literal: true

# The syllabus source of a class and the rules that the extension read from
# it. The rules here are only suggestions: the user confirms them through a
# syllabus preference, and extraction alone never changes grades or events.
# == Schema Information
#
# Table name: brightspace_syllabi
#
#  id                 :bigint           not null, primary key
#  extracted          :jsonb            not null
#  removed_at         :datetime
#  revision           :string           not null
#  source_url         :string
#  title              :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  course_offering_id :bigint           not null
#  source_id          :string
#
# Indexes
#
#  index_brightspace_syllabi_on_course_offering_id  (course_offering_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (course_offering_id => brightspace_course_offerings.id)
#
module Brightspace
  class Syllabus < ApplicationRecord
    include EncodedIds::HashidIdentifiable
    include Brightspace::Removable

    self.table_name = "brightspace_syllabi"

    set_public_id_prefix :bsy, min_hash_length: 12

    belongs_to :course_offering, class_name: "Brightspace::CourseOffering", inverse_of: :syllabus

    validates :course_offering_id, uniqueness: true
    validates :revision, presence: true, length: { maximum: 128 }
    validates :title, length: { maximum: 500 }
    validate :extracted_is_an_object

    private

    # No matcher checks the JSON type of a jsonb column.
    def extracted_is_an_object
      errors.add(:extracted, "must be an object") unless extracted.is_a?(Hash)
    end
  end
end
