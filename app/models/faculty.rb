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
#  index_faculties_on_employee_type             (employee_type)
#  index_faculties_on_rmp_id                    (rmp_id) UNIQUE
#  index_faculties_on_rmp_raw_data              (rmp_raw_data) USING gin
#  index_faculties_on_school                    (school)
#
class Faculty < ApplicationRecord
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :fac

  has_and_belongs_to_many :courses
  has_many :rmp_ratings, dependent: :destroy
  has_many :related_professors, dependent: :destroy
  has_one :rating_distribution, dependent: :destroy
  has_many :teacher_rating_tags, dependent: :destroy
  has_one_attached :photo

  validates :email, presence: true, uniqueness: true
  validates :first_name, :last_name, presence: true
  validates :rmp_id, uniqueness: true, allow_nil: true

  after_create :enqueue_directory_lookup, if: :needs_directory_data?

  scope :faculty_only,        -> { where(employee_type: "faculty") }
  scope :staff_only,          -> { where(employee_type: "staff") }
  scope :by_school,           ->(school) { where(school: school) }
  scope :by_department,       ->(dept) { where(department: dept) }
  scope :with_courses,        -> { joins(:courses).distinct }
  scope :without_courses,     -> { where.missing(:courses) }
  scope :with_directory_data, -> { where.not(directory_last_synced_at: nil) }
  scope :needs_directory_sync, -> {
    where(directory_last_synced_at: nil).or(where(directory_last_synced_at: ...7.days.ago))
  }

  def full_name
    display_name.presence || [ first_name, middle_name, last_name ].compact.join(" ").squish
  end

  def formal_name
    [ title.presence, first_name, middle_name, last_name ].compact.join(" ").squish
  end

  def initials
    "#{first_name[0]}#{last_name[0]}"
  end

  def u_name
    { fwd: "#{first_name[0]}. #{last_name}", rev: "#{last_name}, #{first_name[0]}." }
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

  def calculate_rating_stats
    return {} if rmp_ratings.empty?

    {
      avg_rating: rmp_ratings.average(:clarity_rating)&.round(2),
      avg_difficulty: rmp_ratings.average(:difficulty_rating)&.round(2),
      num_ratings: rmp_ratings.count,
      would_take_again_percent: calculate_would_take_again_percent
    }
  end

  def matched_related_faculty
    Faculty.joins("INNER JOIN related_professors ON related_professors.related_faculty_id = faculties.id")
           .where(related_professors: { faculty_id: id })
           .distinct
  end

  def update_ratings!      = UpdateFacultyRatingsJob.perform_later(id)
  def update_ratings_now!  = UpdateFacultyRatingsJob.perform_now(id)
  def sync_from_directory! = FacultyDirectoryLookupJob.perform_later(id)
  def sync_from_directory_now! = FacultyDirectoryLookupJob.perform_now(id)
  def teaches_courses?     = courses.exists?
  def has_directory_data?  = directory_last_synced_at.present? || directory_raw_data.present?
  def needs_directory_data? = !has_directory_data?

  def rmp_numeric_id
    return nil if rmp_id.blank?

    decoded = Base64.decode64(rmp_id)
    if decoded.start_with?("Teacher-")
      numeric_part = decoded.split("-", 2).last
      return numeric_part if numeric_part.match?(/\A\d+\z/)
    end
    rmp_id
  end

  def rmp_teacher_node
    rmp_raw_data&.dig("teacher", "data", "node")
  end

  def rmp_all_ratings_raw
    rmp_raw_data&.fetch("all_ratings", []) || []
  end

  def rmp_last_updated
    timestamp = rmp_raw_data&.dig("metadata", "last_updated_at")
    return nil if timestamp.blank?

    Time.zone.parse(timestamp)
  rescue ArgumentError
    nil
  end

  def directory_data_age
    return nil unless directory_last_synced_at

    Time.current - directory_last_synced_at
  end

  def photo_display_url
    if photo.attached?
      Rails.application.routes.url_helpers.rails_blob_path(photo, only_path: true)
    else
      photo_url
    end
  end

  def update_photo_from_url!(url)
    return if url.blank?
    return if url.include?("placeholder") || url.include?("Icon_User")
    return if photo_url == url && photo.attached?

    require "open-uri"

    downloaded_image = URI.parse(url).open(
      "User-Agent" => "WITCalendarBot/1.0",
      read_timeout: 10
    )
    filename = "#{email.split("@").first}_photo#{File.extname(URI.parse(url).path)}"
    filename = "#{email.split("@").first}_photo.jpg" if filename.end_with?("_photo")
    photo.attach(io: downloaded_image, filename: filename, content_type: downloaded_image.content_type || "image/jpeg")
    update_column(:photo_url, url) unless photo_url == url # rubocop:disable Rails/SkipsModelValidations
    true
  rescue => e
    Rails.logger.warn("[Faculty] Failed to download photo for #{email}: #{e.message}")
    false
  end

  def self.update_all_ratings!
    with_courses.find_each(&:update_ratings!)
  end

  def self.sync_all_from_directory!
    FacultyDirectorySyncJob.perform_later
  end

  private

  def enqueue_directory_lookup
    last_full_sync = Rails.cache.read("faculty_directory_last_full_sync_at")
    if last_full_sync.present? && last_full_sync > 24.hours.ago
      Rails.logger.info("[Faculty] Skipping individual lookup for #{email} — full sync ran at #{last_full_sync.iso8601}")
      return
    end

    FacultyDirectoryLookupJob.perform_later(id)
  end

  def calculate_would_take_again_percent
    total = rmp_ratings.where.not(would_take_again: nil).count
    return nil if total.zero?

    yes_count = rmp_ratings.where(would_take_again: true).count
    ((yes_count.to_f / total) * 100).round(2)
  end
end
