# frozen_string_literal: true

# == Schema Information
#
# Table name: courses
# Database name: primary
#
#  id             :bigint           not null, primary key
#  course_number  :integer
#  credit_hours   :integer
#  crn            :integer
#  embedding      :vector(1536)
#  end_date       :date
#  grade_mode     :string
#  schedule_type  :string           not null
#  section_number :string           not null
#  start_date     :date
#  subject        :string
#  title          :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  term_id        :bigint           not null
#
# Indexes
#
#  index_courses_on_crn      (crn) UNIQUE
#  index_courses_on_term_id  (term_id)
#
# Foreign Keys
#
#  fk_rails_...  (term_id => terms.id)
#
class Course < ApplicationRecord
  include CourseChangeTrackable
  include PublicIdentifiable

  set_public_id_prefix :crs

  belongs_to :term

  has_and_belongs_to_many :faculties
  has_many :meeting_times, dependent: :destroy
  has_many :rooms, through: :meeting_times
  has_many :enrollments, dependent: :destroy
  has_many :users, through: :enrollments
  has_one :final_exam, dependent: :destroy

  has_neighbors :embedding

  validates :crn, uniqueness: true, allow_nil: true

  # Update term dates when course dates change
  after_save :update_term_dates, if: -> { saved_change_to_start_date? || saved_change_to_end_date? }
  after_destroy :update_term_dates

  scope :with_embeddings, -> { where.not(embedding: nil) }

  enum :schedule_type, {
    hybrid: "HYB",
    laboratory: "LAB",
    lecture: "LEC",
    online_sync_lab: "OLB",
    online_sync_lecture: "OLC",
    rotating_lab: "RLB",
    rotating_lecture: "RLC"
  }

  # Generate the text representation for embedding
  # Combines title, subject, and schedule type for semantic search
  def embedding_text
    parts = [
      title,
      subject,
      schedule_type_description
    ].compact

    parts.join(" ")
  end

  def prefix
    if subject =~ /\(([^)]+)\)/
      $1
    else
      "UNKNWN"
    end
  end

  # Human-readable schedule type description
  def schedule_type_description
    return nil unless schedule_type

    {
      "hybrid"              => "hybrid in-person and online",
      "laboratory"          => "laboratory hands-on",
      "lecture"             => "lecture",
      "online_sync_lab"     => "online synchronous lab",
      "online_sync_lecture" => "online synchronous lecture",
      "rotating_lab"        => "rotating laboratory",
      "rotating_lecture"    => "rotating lecture"
    }[schedule_type]
  end

  # Find courses with similar content/subject matter
  def similar_courses(limit: 10, distance: "cosine")
    return self.class.none if embedding.nil?

    self.class.nearest_neighbors(:embedding, embedding, distance: distance)
        .where.not(id: id)
        .limit(limit)
  end

  # Search for courses by semantic query
  # Requires passing an embedding vector generated from a search query
  def self.semantic_search(query_embedding, limit: 10, distance: "cosine")
    nearest_neighbors(:embedding, query_embedding, distance: distance)
      .limit(limit)
  end

  private

  # Update the term's start_date and end_date based on all courses
  def update_term_dates
    term.update_dates_from_courses!
  end

end
