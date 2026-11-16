# frozen_string_literal: true

# == Schema Information
#
# Table name: faculties
#
#  id                       :bigint           not null, primary key
#  department               :string
#  directory_last_synced_at :datetime
#  directory_raw_data       :jsonb
#  display_name             :string
#  email                    :string           not null
#  embedding                :vector(1536)
#  embedding_digest         :string(64)
#  employee_type            :string
#  first_name               :string           not null
#  last_name                :string           not null
#  middle_name              :string
#  office_location          :string
#  phone                    :string
#  photo_url                :string
#  rmp_raw_data             :jsonb
#  school                   :string
#  title                    :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  rmp_id                   :string
#
# Indexes
#
#  index_faculties_on_department                (department)
#  index_faculties_on_directory_last_synced_at  (directory_last_synced_at)
#  index_faculties_on_directory_raw_data        (directory_raw_data) USING gin
#  index_faculties_on_email                     (email) UNIQUE
#  index_faculties_on_embedding                 (embedding vector_cosine_ops) USING hnsw
#  index_faculties_on_employee_type             (employee_type)
#  index_faculties_on_lower_email               (lower((email)::text))
#  index_faculties_on_rmp_id                    (rmp_id) UNIQUE
#  index_faculties_on_rmp_raw_data              (rmp_raw_data) USING gin
#  index_faculties_on_school                    (school)
#
class Faculty < ApplicationRecord
  include Embeddable
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :fac

  has_many :course_faculties, dependent: :destroy, inverse_of: :faculty
  has_many :courses, through: :course_faculties
  has_many :rmp_ratings, dependent: :destroy
  has_many :related_professors, dependent: :destroy
  has_one :rating_distribution, dependent: :destroy
  has_many :teacher_rating_tags, dependent: :destroy
  has_one_attached :photo

  validates :email, presence: true, uniqueness: true
  validates :first_name, :last_name, presence: true
  validates :rmp_id, uniqueness: true, allow_nil: true

  after_create_commit :enqueue_directory_lookup, if: :needs_directory_data?

  scope :faculty_only,        -> { where(employee_type: "faculty") }
  scope :staff_only,          -> { where(employee_type: "staff") }
  scope :with_courses,        -> { joins(:courses).distinct }
  # Faculty who teach a course that is not cancelled in the current term or a
  # later term. Only these need a RateMyProfessor ID. The weekly RateMyProfessor
  # jobs and the Missing RMP IDs page use this scope, not every professor who
  # ever taught (#712).
  scope :teaching_current_or_future, -> { where(id: CourseFaculty.current_or_future.select(:faculty_id)) }
  scope :missing_rmp_id, -> { teaching_current_or_future.where(rmp_id: nil) }

  def full_name
    display_name.presence || [ first_name, middle_name, last_name ].compact.join(" ").squish
  end

  def formal_name
    [ title.presence, first_name, middle_name, last_name ].compact.join(" ").squish
  end

  def initials
    "#{first_name[0]}#{last_name[0]}"
  end

  # Who this person is, in the words a student would use to look for them. The
  # directory fields are the stable part; ratings change every term, so they
  # stay out of the vector.
  def embedding_text
    [ full_name, title, department, school ].compact_blank.join(". ")
  end

  # Instructors whose subject looks like this one's, nearest first. Only
  # people who teach are offered, because the catalog only shows those.
  def similar_instructors(limit: Embeddable::DEFAULT_SIMILAR_LIMIT)
    similar(limit: limit, among: Faculty.joins(:courses).select("faculties.id"))
  end

  def rmp_stats
    return nil unless rating_distribution

    {
      avg_rating: rating_distribution.avg_rating&.to_f,
      avg_difficulty: rating_distribution.avg_difficulty&.to_f,
      num_ratings: rating_distribution.num_ratings,
      would_take_again_percent: rating_distribution.would_take_again_percent&.to_f
    }
  end

  def teaches_courses? = courses.exists?
  def needs_directory_data? = directory_last_synced_at.nil? && directory_raw_data.blank?

  def rmp_numeric_id
    return nil if rmp_id.blank?

    decoded = Base64.decode64(rmp_id)
    if decoded.start_with?("Teacher-")
      numeric_part = decoded.split("-", 2).last
      return numeric_part if numeric_part.match?(/\A\d+\z/)
    end
    rmp_id
  end

  private

  def enqueue_directory_lookup
    last_full_sync = Rails.cache.read(Faculties::DirectorySyncJob::LAST_FULL_SYNC_CACHE_KEY)
    if last_full_sync.present? && last_full_sync > Faculties::DirectoryLookupJob::FRESH_FOR.ago
      Rails.logger.info("[Faculty] Skipping individual lookup for #{email} — full sync ran at #{last_full_sync.iso8601}")
      return
    end

    Faculties::DirectoryLookupJob.perform_later(id)
  end
end
