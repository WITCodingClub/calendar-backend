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

  validates :uid, presence: true, uniqueness: true

  enum :season, {
    spring: 1,
    fall: 2,
    summer: 3
  }

  def name
    "#{season.to_s.capitalize} #{year}"
  end

  # Update start_date and end_date from course data
  # Should be called after importing courses or when course dates change
  def update_dates_from_courses!
    return if courses.empty?

    update!(
      start_date: courses.where.not(start_date: nil).minimum(:start_date),
      end_date: courses.where.not(end_date: nil).maximum(:end_date)
    )
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
  # Checks which term's date range contains today, falling back to season-based logic
  def self.current
    today = Time.zone.today

    # First, try to find a term where today falls within start_date and end_date
    active_term = where.not(start_date: nil, end_date: nil)
                       .where("start_date <= ? AND end_date >= ?", today, today)
                       .first

    return active_term if active_term

    # Fallback to season-based logic if no term has dates set
    current_year = today.year

    # Determine current season based on date ranges:
    # Spring: January 1 - May 31
    # Summer: June 1 - July 31
    # Fall: August 1 - December 31
    current_season = if today.month >= 8 # August - December
                       :fall
                     elsif today.month >= 6 # June - July
                       :summer
                     else # January - May
                       :spring
                     end

    find_by(year: current_year, season: current_season)
  end

  # Returns the next academic term after the current term
  # Uses date-based logic if available, falls back to season progression
  def self.next
    today = Time.zone.today
    current_term = current

    # If we have terms with dates, find the next upcoming term by start_date
    if where.not(start_date: nil).exists?
      # Find the earliest term that starts after today
      upcoming = where.not(start_date: nil)
                      .where("start_date > ?", today)
                      .order(:start_date)
                      .first

      return upcoming if upcoming
    end

    # Fallback to season-based progression
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
