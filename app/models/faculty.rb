# == Schema Information
#
# Table name: faculties
# Database name: primary
#
#  id         :bigint           not null, primary key
#  email      :string           not null
#  first_name :string           not null
#  last_name  :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  rmp_id     :string
#
# Indexes
#
#  index_faculties_on_email   (email) UNIQUE
#  index_faculties_on_rmp_id  (rmp_id) UNIQUE
#
class Faculty < ApplicationRecord
  has_and_belongs_to_many :courses
  has_many :rmp_ratings, dependent: :destroy
  has_many :related_professors, dependent: :destroy
  has_one :rating_distribution, dependent: :destroy
  has_many :teacher_rating_tags, dependent: :destroy

  validates :rmp_id, uniqueness: true, allow_nil: true

  def full_name
    "#{first_name} #{last_name}"
  end

  def initials
    "#{first_name[0]}#{last_name[0]}"
  end

  def u_name
    def fwd
      "#{first_name[0]}. #{last_name}"
    end

    def rev
      "#{last_name}, #{first_name[0]}."
    end
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
           .where("related_professors.faculty_id = ?", id)
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

  # Class method to update all faculty ratings
  def self.update_all_ratings!
    find_each do |faculty|
      faculty.update_ratings!
    end
  end

  private

  def calculate_would_take_again_percent
    total = rmp_ratings.where.not(would_take_again: nil).count
    return nil if total.zero?

    yes_count = rmp_ratings.where(would_take_again: true).count
    ((yes_count.to_f / total) * 100).round(2)
  end
end
