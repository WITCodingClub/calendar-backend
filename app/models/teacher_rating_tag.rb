# frozen_string_literal: true

class TeacherRatingTag < ApplicationRecord
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :trt

  belongs_to :faculty

  validates :rmp_legacy_id, presence: true, uniqueness: { scope: :faculty_id }
  validates :tag_name, presence: true
  validates :tag_count, numericality: { greater_than_or_equal_to: 0 }

  scope :ordered_by_count, -> { order(tag_count: :desc) }
  scope :top_tags,         ->(limit = 5) { ordered_by_count.limit(limit) }
end
