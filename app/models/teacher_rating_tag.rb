# == Schema Information
#
# Table name: teacher_rating_tags
# Database name: primary
#
#  id            :bigint           not null, primary key
#  tag_count     :integer          default(0)
#  tag_name      :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  faculty_id    :bigint           not null
#  rmp_legacy_id :integer          not null
#
# Indexes
#
#  index_teacher_rating_tags_on_faculty_id                    (faculty_id)
#  index_teacher_rating_tags_on_faculty_id_and_rmp_legacy_id  (faculty_id,rmp_legacy_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (faculty_id => faculties.id)
#
class TeacherRatingTag < ApplicationRecord
  belongs_to :faculty

  validates :rmp_legacy_id, presence: true, uniqueness: { scope: :faculty_id }
  validates :tag_name, presence: true
  validates :tag_count, numericality: { greater_than_or_equal_to: 0 }

  scope :ordered_by_count, -> { order(tag_count: :desc) }
  scope :top_tags, ->(limit = 5) { ordered_by_count.limit(limit) }
end
