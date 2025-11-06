# frozen_string_literal: true

# == Schema Information
#
# Table name: terms
# Database name: primary
#
#  id         :bigint           not null, primary key
#  season     :integer
#  uid        :integer          not null
#  year       :integer
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_terms_on_uid              (uid) UNIQUE
#  index_terms_on_year_and_season  (year,season) UNIQUE
#
class Term < ApplicationRecord
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
  def self.current
    today = Time.zone.today
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
