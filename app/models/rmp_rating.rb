# frozen_string_literal: true

# == Schema Information
#
# Table name: rmp_ratings
#
#  id                   :bigint           not null, primary key
#  attendance_mandatory :string
#  clarity_rating       :integer
#  comment              :text
#  course_name          :string
#  difficulty_rating    :integer
#  grade                :string
#  helpful_rating       :integer
#  is_for_credit        :boolean
#  is_for_online_class  :boolean
#  rating_date          :datetime
#  rating_tags          :string
#  thumbs_down_total    :integer          default(0)
#  thumbs_up_total      :integer          default(0)
#  would_take_again     :boolean
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  faculty_id           :bigint           not null
#  rmp_id               :string           not null
#
# Indexes
#
#  index_rmp_ratings_on_faculty_id  (faculty_id)
#  index_rmp_ratings_on_rmp_id      (rmp_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (faculty_id => faculties.id)
#
class RmpRating < ApplicationRecord
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :rmp, min_hash_length: 12

  belongs_to :faculty

  validates :rmp_id, presence: true, uniqueness: true

  scope :recent,   -> { order(rating_date: :desc) }
  scope :positive, -> { where(clarity_rating: 4..) }
  scope :negative, -> { where(clarity_rating: ..2) }

  def overall_sentiment
    return "neutral" if clarity_rating.blank?

    if clarity_rating >= 4     then "positive"
    elsif clarity_rating <= 2  then "negative"
    else                            "neutral"
    end
  end
end
