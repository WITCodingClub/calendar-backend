# frozen_string_literal: true

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
