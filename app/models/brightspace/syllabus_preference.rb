# frozen_string_literal: true

# Syllabus rules and dates that the user confirmed or edited, with their
# source references. source_revision names the syllabus revision that the
# user reviewed. Nothing here changes grades or calendar events by itself.
# == Schema Information
#
# Table name: brightspace_syllabus_preferences
#
#  id                 :bigint           not null, primary key
#  confirmed          :jsonb            not null
#  source_revision    :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  course_offering_id :bigint           not null
#  user_id            :bigint           not null
#
# Indexes
#
#  index_brightspace_syllabus_preferences_on_course_offering_id  (course_offering_id) UNIQUE
#  index_brightspace_syllabus_preferences_on_user_id             (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (course_offering_id => brightspace_course_offerings.id)
#  fk_rails_...  (user_id => users.id)
#
module Brightspace
  class SyllabusPreference < ApplicationRecord
    include EncodedIds::HashidIdentifiable
    include Brightspace::OwnedByClassUser
    include Brightspace::VersionBumping

    set_public_id_prefix :bsp, min_hash_length: 12

    MAX_BYTES = 200_000

    validates :course_offering_id, uniqueness: true
    validates :source_revision, presence: true, length: { maximum: 128 }
    validate :confirmed_format

    private

    # No matcher checks the JSON type or size of a jsonb column.
    def confirmed_format
      if !confirmed.is_a?(Hash)
        errors.add(:confirmed, "must be an object")
      elsif confirmed.to_json.bytesize > MAX_BYTES
        errors.add(:confirmed, "is too large")
      end
    end
  end
end
