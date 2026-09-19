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
#  embedding            :vector(1536)
#  embedding_digest     :string(64)
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
#  index_rmp_ratings_on_embedding   (embedding) USING hnsw
#  index_rmp_ratings_on_faculty_id  (faculty_id)
#  index_rmp_ratings_on_rmp_id      (rmp_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (faculty_id => faculties.id)
#
class RmpRating < ApplicationRecord
  include Embeddable
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :rmp, min_hash_length: 12

  belongs_to :faculty

  validates :rmp_id, presence: true, uniqueness: true

  scope :recent,   -> { order(rating_date: :desc) }
  scope :positive, -> { where(clarity_rating: 4..) }
  scope :negative, -> { where(clarity_rating: ..2) }

  # The review itself, with the course it was written about. A review with no
  # comment gets no vector, because the ratings alone say nothing a search for
  # "lots of group projects" could match.
  def embedding_text
    return nil if comment.blank?

    [ course_name, comment ].compact_blank.join(": ")
  end

  def overall_sentiment
    return "neutral" if clarity_rating.blank?

    if clarity_rating >= 4     then "positive"
    elsif clarity_rating <= 2  then "negative"
    else                            "neutral"
    end
  end
end
