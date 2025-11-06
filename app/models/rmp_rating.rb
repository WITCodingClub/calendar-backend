# frozen_string_literal: true

# == Schema Information
#
# Table name: rmp_ratings
# Database name: primary
#
#  id                   :bigint           not null, primary key
#  attendance_mandatory :string
#  clarity_rating       :integer
#  comment              :text
#  course_name          :string
#  difficulty_rating    :integer
#  embedding            :vector
#  grade                :string
#  helpful_rating       :integer
#  is_for_credit        :boolean
#  is_for_online_class  :boolean
#  rating_date          :datetime
#  rating_tags          :text
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
  belongs_to :faculty

  has_neighbors :embedding

  validates :rmp_id, presence: true, uniqueness: true

  scope :recent, -> { order(rating_date: :desc) }
  scope :positive, -> { where(clarity_rating: 4..) }
  scope :negative, -> { where(clarity_rating: ..2) }
  scope :with_embeddings, -> { where.not(embedding: nil) }

  def overall_sentiment
    return "neutral" if clarity_rating.blank?

    if clarity_rating >= 4
      "positive"
    elsif clarity_rating <= 2
      "negative"
    else
      "neutral"
    end
  end

  # Find similar ratings based on comment embeddings
  def similar_ratings(limit: 10, distance: "cosine")
    return self.class.none if embedding.nil?

    self.class.nearest_neighbors(:embedding, embedding, distance: distance)
        .where.not(id: id)
        .limit(limit)
  end

  # Find similar comments from other faculties
  def similar_comments_other_faculties(limit: 10)
    return self.class.none if embedding.nil?

    self.class.nearest_neighbors(:embedding, embedding, distance: "cosine")
        .where.not(faculty_id: faculty_id)
        .limit(limit)
  end

end
