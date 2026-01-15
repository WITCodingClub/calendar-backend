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
#  status         :string           default("active"), not null
#  subject        :string
#  title          :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  term_id        :bigint           not null
#
# Indexes
#
#  index_courses_on_crn              (crn)
#  index_courses_on_crn_and_term_id  (crn,term_id) UNIQUE
#  index_courses_on_status           (status)
#  index_courses_on_term_id          (term_id)
#
# Foreign Keys
#
#  fk_rails_...  (term_id => terms.id)
#
class Course < ApplicationRecord
  include CourseChangeTrackable
  include PublicIdentifiable
  include Embeddable

  set_public_id_prefix :crs

  belongs_to :term

  has_and_belongs_to_many :faculties
  has_many :meeting_times, dependent: :destroy
  has_many :rooms, through: :meeting_times
  has_many :enrollments, dependent: :destroy
  has_many :users, through: :enrollments
  has_one :final_exam, dependent: :destroy

  has_neighbors :embedding

  validates :crn, uniqueness: { scope: :term_id, message: "has already been taken for this term" }, allow_nil: true

  after_destroy :update_term_dates
  # Update term dates when course dates change
  after_save :update_term_dates, if: -> { saved_change_to_start_date? || saved_change_to_end_date? }

  enum :status, { active: "active", cancelled: "cancelled" }

  enum :schedule_type, {
    hybrid: "HYB",
    independent_study: "IND",
    laboratory: "LAB",
    lecture: "LEC",
    online: "ONL",
    online_sync_lab: "OLB",
    online_sync_lecture: "OLC",
    rotating_lab: "RLB",
    rotating_lecture: "RLC",
    study_abroad: "SAB"
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
      "independent_study"   => "independent study",
      "laboratory"          => "laboratory hands-on",
      "lecture"             => "lecture",
      "online"              => "online asynchronous",
      "online_sync_lab"     => "online synchronous lab",
      "online_sync_lecture" => "online synchronous lecture",
      "rotating_lab"        => "rotating laboratory",
      "rotating_lecture"    => "rotating lecture",
      "study_abroad"        => "study abroad"
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

  # Filter meeting times to deduplicate entries with same day/time
  # Prefers meeting times with valid locations over TBD/placeholder ones
  def filtered_meeting_times
    meeting_times.group_by { |mt| [mt.day_of_week, mt.begin_time, mt.end_time] }
                 .map do |_key, meeting_times_group|
                   next meeting_times_group.first if meeting_times_group.size == 1

                   # Prefer non-TBD locations over TBD
                   non_tbd = meeting_times_group.reject { |mt| tbd_location?(mt) }
                   non_tbd.any? ? non_tbd.first : meeting_times_group.first
                 end
  end

  private

  # Check if meeting time has a TBD/placeholder location
  def tbd_location?(meeting_time)
    building = meeting_time.building
    room = meeting_time.room

    return true if building.nil? || room.nil?

    # Check building
    if building.name.blank? ||
       building.abbreviation.blank? ||
       building.name&.downcase&.include?("to be determined") ||
       building.name&.downcase == "tbd" ||
       building.abbreviation&.downcase == "tbd"
      return true
    end

    # Check room (room 0 or "0" indicates TBD)
    return true if room.number.to_s == "0"

    false
  end

  # Update the term's start_date and end_date based on all courses
  def update_term_dates
    term.update_dates_from_courses!
  end

end
