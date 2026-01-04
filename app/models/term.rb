# frozen_string_literal: true

# == Schema Information
#
# Table name: terms
# Database name: primary
#
#  id                  :bigint           not null, primary key
#  catalog_imported    :boolean          default(FALSE), not null
#  catalog_imported_at :datetime
#  end_date            :date
#  season              :integer
#  start_date          :date
#  uid                 :integer          not null
#  year                :integer
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#
# Indexes
#
#  index_terms_on_uid              (uid) UNIQUE
#  index_terms_on_year_and_season  (year,season) UNIQUE
#
class Term < ApplicationRecord
  include PublicIdentifiable

  set_public_id_prefix :trm

  has_many :courses, dependent: :destroy
  has_many :enrollments, dependent: :destroy
  has_many :final_exams, dependent: :destroy

  validates :uid, presence: true, uniqueness: true

  enum :season, {
    spring: 1,
    fall: 2,
    summer: 3
  }

  # Scope for current and future terms (for finals schedule uploads)
  scope :current_and_future, -> {
    current_term = Term.current
    return none unless current_term

    # Include current term and any terms after it
    where("(year > ?) OR (year = ? AND season >= ?)",
          current_term.year, current_term.year, seasons[current_term.season])
      .order(year: :desc, season: :desc)
  }

  def name
    "#{season.to_s.capitalize} #{year}"
  end

  # Update start_date and end_date from course data
  # Only applies dates that are valid for the term year
  def update_dates_from_courses!
    return if courses.empty?

    # Only consider courses with dates in a valid year range
    valid_courses = courses.where.not(start_date: nil, end_date: nil)
                           .where("EXTRACT(YEAR FROM start_date) >= ? AND EXTRACT(YEAR FROM start_date) <= ?", year - 1, year)
                           .where("EXTRACT(YEAR FROM end_date) >= ? AND EXTRACT(YEAR FROM end_date) <= ?", year, year + 1)

    return if valid_courses.empty?

    new_start = valid_courses.minimum(:start_date)
    new_end = valid_courses.maximum(:end_date)

    update!(start_date: new_start, end_date: new_end)
  end

  # Check if term is currently active based on dates
  # @return [Boolean] true if today is within term dates
  def active?
    return false if start_date.nil? || end_date.nil?

    today = Time.zone.today
    today >= start_date && today <= end_date
  end

  # Check if term is upcoming (starts in the future)
  # @return [Boolean] true if term starts after today
  def upcoming?
    return false if start_date.nil?

    Time.zone.today < start_date
  end

  # Check if term has ended (is in the past)
  # @return [Boolean] true if term ended before today
  def past?
    return false if end_date.nil?

    Time.zone.today > end_date
  end

  # Check if term is current or future (not retroactive)
  # @return [Boolean] true if term is not in the past
  def current_or_future?
    !past?
  end

  # Find a term by its UID
  # @param uid [Integer] the term UID
  # @return [Term, nil] the term if found, nil otherwise
  def self.find_by_uid(uid)
    find_by(uid: uid)
  end

  # Find a term by its UID, raises if not found
  # @param uid [Integer] the term UID
  # @return [Term] the term
  # @raise [ActiveRecord::RecordNotFound] if term not found
  def self.find_by_uid!(uid)
    find_by!(uid: uid)
  end

  # Returns the current academic term based on today's date
  # Uses year/season-based logic as primary, with date validation
  # @return [Term, nil] the current term, or nil if none found
  def self.current
    today = Time.zone.today
    current_year = today.year

    # Determine expected season based on month
    # Aug-Dec: Fall semester
    # Jan-May: Spring semester
    # Jun-Jul: Summer semester
    expected_season = case today.month
                      when 1..5 then :spring
                      when 6..7 then :summer
                      when 8..12 then :fall
                      end

    # For late December (after Fall ends), look ahead to Spring of next year
    if today.month == 12 && today.day >= 15
      spring_next_year = find_by(year: current_year + 1, season: :spring)
      return spring_next_year if spring_next_year
    end

    # Priority 1: Look for expected term in current year
    expected_term = find_by(year: current_year, season: expected_season)
    return expected_term if expected_term

    # Priority 2: If we're in spring months but no spring term, check if fall is still active
    if expected_season == :spring
      fall_term = find_by(year: current_year - 1, season: :fall)
      return fall_term if fall_term&.active?
    end

    # Priority 3: Find the next upcoming term
    upcoming_term = where.not(start_date: nil)
                         .where("start_date > ?", today)
                         .where("year >= ?", current_year)
                         .order(start_date: :asc)
                         .first

    return upcoming_term if upcoming_term

    # Priority 4: Fall back to most recent term by year/season
    order(year: :desc, season: :desc).first
  end

  # Returns the next academic term after the current term
  # Uses season progression logic to determine the next term
  # @return [Term, nil] the next term, or nil if none found
  def self.next
    current_term = current
    return nil unless current_term

    # Determine next term based on season progression:
    # Fall -> Spring (next year)
    # Spring -> Summer (same year)
    # Summer -> Fall (same year)
    case current_term.season.to_sym
    when :fall
      find_by(year: current_term.year + 1, season: :spring)
    when :spring
      find_by(year: current_term.year, season: :summer)
    when :summer
      find_by(year: current_term.year, season: :fall)
    end
  end

  # Convenience method to get current term UID
  # @return [Integer, nil] the UID of the current term
  def self.current_uid
    current&.uid
  end

  # Convenience method to get next term UID
  # @return [Integer, nil] the UID of the next term
  def self.next_uid
    self.next&.uid
  end

  # Check if a term exists by UID
  # @param uid [Integer] the term UID
  # @return [Boolean] true if term exists
  def self.exists_by_uid?(uid)
    exists?(uid: uid)
  end

  private

  def uniqueness_of_year_and_semester
    return unless Term.exists?(year: year, semester: semester)

    errors.add(:base, "Term with year #{year} and semester #{semester} already exists")

  end


end
