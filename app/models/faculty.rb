# frozen_string_literal: true

# == Schema Information
#
# Table name: faculties
# Database name: primary
#
#  id           :bigint           not null, primary key
#  email        :string           not null
#  embedding    :vector(1536)
#  first_name   :string           not null
#  last_name    :string           not null
#  rmp_raw_data :jsonb
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  rmp_id       :string
#
# Indexes
#
#  index_faculties_on_email         (email) UNIQUE
#  index_faculties_on_rmp_id        (rmp_id) UNIQUE
#  index_faculties_on_rmp_raw_data  (rmp_raw_data) USING gin
#
class Faculty < ApplicationRecord
  include PublicIdentifiable

  set_public_id_prefix :fac

  has_and_belongs_to_many :courses
  has_many :rmp_ratings, dependent: :destroy
  has_many :related_professors, dependent: :destroy
  has_one :rating_distribution, dependent: :destroy
  has_many :teacher_rating_tags, dependent: :destroy

  has_neighbors :embedding

  validates :rmp_id, uniqueness: true, allow_nil: true

  scope :with_embeddings, -> { where.not(embedding: nil) }

  def full_name
    "#{first_name} #{last_name}"
  end

  def initials
    "#{first_name[0]}#{last_name[0]}"
  end

  def u_name
    {
      fwd: "#{first_name[0]}. #{last_name}",
      rev: "#{last_name}, #{first_name[0]}."
    }
  end

  # Get RMP aggregate stats (from rating_distribution table)
  def rmp_stats
    return nil unless rating_distribution

    {
      avg_rating: rating_distribution.avg_rating&.to_f,
      avg_difficulty: rating_distribution.avg_difficulty&.to_f,
      num_ratings: rating_distribution.num_ratings,
      would_take_again_percent: rating_distribution.would_take_again_percent&.to_f
    }
  end

  # Calculate aggregate rating statistics from stored ratings
  def calculate_rating_stats
    return {} if rmp_ratings.empty?

    {
      avg_rating: rmp_ratings.average(:clarity_rating)&.round(2),
      avg_difficulty: rmp_ratings.average(:difficulty_rating)&.round(2),
      num_ratings: rmp_ratings.count,
      would_take_again_percent: calculate_would_take_again_percent
    }
  end

  # Get matched related faculty (professors that exist in our database)
  def matched_related_faculty
    Faculty.joins("INNER JOIN related_professors ON related_professors.related_faculty_id = faculties.id")
           .where(related_professors: { faculty_id: id })
           .distinct
  end

  # Trigger job to update ratings from Rate My Professor
  def update_ratings!
    UpdateFacultyRatingsJob.perform_later(id)
  end

  # Synchronously update ratings (useful for console/rake tasks)
  def update_ratings_now!
    UpdateFacultyRatingsJob.perform_now(id)
  end

  # Access raw RMP GraphQL data
  def rmp_graph_data
    return {} if rmp_raw_data.blank?

    rmp_raw_data
  end

  # Get the teacher node from raw data
  def rmp_teacher_node
    rmp_raw_data.dig("teacher", "data", "node")
  end

  # Get all ratings from raw data
  def rmp_all_ratings_raw
    rmp_raw_data["all_ratings"] || []
  end

  # Get metadata about the last RMP data fetch
  def rmp_last_updated
    timestamp = rmp_raw_data.dig("metadata", "last_updated_at")
    return nil if timestamp.blank?

    Time.zone.parse(timestamp)
  rescue ArgumentError
    nil
  end

  # Reconstruct GraphQL edges structure for ratings
  def rmp_ratings_as_edges
    rmp_all_ratings_raw.map.with_index do |rating, index|
      {
        cursor: Base64.strict_encode64("arrayconnection:#{index}"),
        node: rating
      }
    end
  end

  # Class method to update all faculty ratings
  def self.update_all_ratings!
    find_each do |faculty|
      faculty.update_ratings!
    end
  end

  # Find faculty with similar teaching profiles based on aggregated embedding
  def similar_faculty(limit: 10, distance: "cosine")
    return self.class.none if embedding.nil?

    self.class.nearest_neighbors(:embedding, embedding, distance: distance)
        .where.not(id: id)
        .limit(limit)
  end

  # Search for faculty by semantic query
  # Requires passing an embedding vector generated from a search query
  def self.semantic_search(query_embedding, limit: 10, distance: "cosine")
    nearest_neighbors(:embedding, query_embedding, distance: distance)
      .limit(limit)
  end

  private

  def calculate_would_take_again_percent
    total = rmp_ratings.where.not(would_take_again: nil).count
    return nil if total.zero?

    yes_count = rmp_ratings.where(would_take_again: true).count
    ((yes_count.to_f / total) * 100).round(2)
  end

end
