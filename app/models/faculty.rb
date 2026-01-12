# frozen_string_literal: true

# == Schema Information
#
# Table name: faculties
# Database name: primary
#
#  id                       :bigint           not null, primary key
#  department               :string
#  directory_last_synced_at :datetime
#  directory_raw_data       :jsonb
#  display_name             :string
#  email                    :string           not null
#  embedding                :vector(1536)
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
  include PublicIdentifiable

  set_public_id_prefix :fac

  has_and_belongs_to_many :courses
  has_many :rmp_ratings, dependent: :destroy
  has_many :related_professors, dependent: :destroy
  has_one :rating_distribution, dependent: :destroy
  has_many :teacher_rating_tags, dependent: :destroy

  has_one_attached :photo

  has_neighbors :embedding

  validates :rmp_id, uniqueness: true, allow_nil: true

  # Callbacks
  after_create :enqueue_directory_lookup, if: :needs_directory_data?

  # Scopes
  scope :with_embeddings, -> { where.not(embedding: nil) }
  scope :faculty_only, -> { where(employee_type: "faculty") }
  scope :staff_only, -> { where(employee_type: "staff") }
  scope :by_school, ->(school) { where(school: school) }
  scope :by_department, ->(department) { where(department: department) }
  scope :needs_directory_sync, -> { where(directory_last_synced_at: nil).or(where("directory_last_synced_at < ?", 7.days.ago)) }
  scope :with_directory_data, -> { where.not(directory_last_synced_at: nil) }
  scope :with_courses, -> { joins(:courses).distinct }
  scope :without_courses, -> { where.missing(:courses) }

  def full_name
    display_name.presence || [first_name, middle_name, last_name].compact.join(" ").squish
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

  # Extract numeric RMP ID from base64-encoded GraphQL ID
  # RMP stores IDs as base64("Teacher-12345") but URLs use just the numeric part
  def rmp_numeric_id
    return nil if rmp_id.blank?

    decoded = Base64.decode64(rmp_id)

    # Validate expected format "Teacher-12345" and extract numeric part
    if decoded.start_with?("Teacher-")
      numeric_part = decoded.split("-", 2).last
      return numeric_part if numeric_part.match?(/\A\d+\z/)
    end

    # If format doesn't match, assume rmp_id is already numeric
    rmp_id
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

  # Class method to update all faculty ratings (only those who teach courses)
  def self.update_all_ratings!
    with_courses.find_each do |faculty|
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

  # Get formatted name for different uses (includes title)
  def formal_name
    [title.presence, first_name, middle_name, last_name].compact.join(" ").squish
  end

  # Check if record has directory data
  def has_directory_data?
    directory_last_synced_at.present? || directory_raw_data.present?
  end

  # Check if directory data needs to be fetched
  # Returns false if we already have directory data (from sync or prior lookup)
  def needs_directory_data?
    !has_directory_data?
  end

  # Check if faculty teaches any courses
  def teaches_courses?
    courses.exists?
  end

  # Trigger directory sync for this faculty member
  def sync_from_directory!
    FacultyDirectoryLookupJob.perform_later(id)
  end

  # Synchronously sync from directory (useful for console/rake tasks)
  def sync_from_directory_now!
    FacultyDirectoryLookupJob.perform_now(id)
  end

  # Get directory data age
  def directory_data_age
    return nil unless directory_last_synced_at

    Time.current - directory_last_synced_at
  end

  # Class method to sync all faculty from directory
  def self.sync_all_from_directory!
    FacultyDirectorySyncJob.perform_later
  end

  # Download and attach photo from URL if it changed
  def update_photo_from_url!(url)
    return if url.blank?
    return if url.include?("placeholder") || url.include?("Icon_User")

    # Skip if URL hasn't changed
    return if photo_url == url && photo.attached?

    require "open-uri"

    begin
      # Download the image
      downloaded_image = URI.parse(url).open(
        "User-Agent" => "WITCalendarBot/1.0",
        read_timeout: 10
      )

      # Determine filename and content type
      filename = "#{email.split('@').first}_photo#{File.extname(URI.parse(url).path)}"
      filename = "#{email.split('@').first}_photo.jpg" if filename.end_with?("_photo")

      content_type = downloaded_image.content_type || "image/jpeg"

      # Attach the image
      photo.attach(
        io: downloaded_image,
        filename: filename,
        content_type: content_type
      )

      # Update the URL to track what we downloaded
      update_column(:photo_url, url) unless photo_url == url

      Rails.logger.info("[Faculty] Photo downloaded for #{email}")
      true
    rescue => e
      Rails.logger.warn("[Faculty] Failed to download photo for #{email}: #{e.message}")
      false
    end
  end

  # Get the photo URL (either local ActiveStorage or external)
  def photo_display_url
    if photo.attached?
      Rails.application.routes.url_helpers.rails_blob_path(photo, only_path: true)
    else
      photo_url
    end
  end

  private

  def enqueue_directory_lookup
    FacultyDirectoryLookupJob.perform_later(id)
  end

  def calculate_would_take_again_percent
    total = rmp_ratings.where.not(would_take_again: nil).count
    return nil if total.zero?

    yes_count = rmp_ratings.where(would_take_again: true).count
    ((yes_count.to_f / total) * 100).round(2)
  end

end
