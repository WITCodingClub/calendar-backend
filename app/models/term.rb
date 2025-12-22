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
  # Prioritizes date-based logic using actual course dates, with season-based fallback
  # @return [Term, nil] the current term, or nil if none found
  def self.current
    today = Time.zone.today

    # Priority 1: Find term where today falls within actual start_date and end_date
    active_term = where.not(start_date: nil, end_date: nil)
                       .where("start_date <= ? AND end_date >= ?", today, today)
                       .first

    return active_term if active_term

    # Priority 2: Check if we're past the end of the most recent term
    # If so, return the next term (even if it doesn't have dates yet)
    most_recent = where.not(end_date: nil)
                       .where("end_date < ?", today)
                       .order(end_date: :desc)
                       .first

    if most_recent
      # We're past a term's end date - return the next term in sequence
      next_term_after_recent = case most_recent.season.to_sym
                               when :fall
                                 find_by(year: most_recent.year + 1, season: :spring)
                               when :spring
                                 find_by(year: most_recent.year, season: :summer)
                               when :summer
                                 find_by(year: most_recent.year, season: :fall)
                               end

      return next_term_after_recent if next_term_after_recent
    end

    # Priority 3: Find the most recently started term with dates (for longer gaps)
    most_recent_started = where.not(start_date: nil)
                               .where("start_date <= ?", today)
                               .order(start_date: :desc)
                               .first

    return most_recent_started if most_recent_started

    # Priority 4: Fallback to season-based logic for terms without dates
    Rails.logger.warn("No terms with dates found, falling back to season-based logic")
    
    current_year = today.year
    current_season = case today.month
                     when 8..12 then :fall
                     when 6..7 then :summer
                     else :spring
                     end

    find_by(year: current_year, season: current_season)
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
