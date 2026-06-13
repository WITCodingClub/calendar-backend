# frozen_string_literal: true

# == Schema Information
#
# Table name: terms
#
#  id                    :bigint           not null, primary key
#  catalog_import_failed :boolean          default(FALSE), not null
#  catalog_imported      :boolean          default(FALSE), not null
#  catalog_imported_at   :datetime
#  catalog_importing     :boolean          default(FALSE), not null
#  end_date              :date
#  season                :integer          not null
#  start_date            :date
#  uid                   :integer          not null
#  year                  :integer          not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  catalog_import_job_id :string
#
# Indexes
#
#  index_terms_on_uid              (uid) UNIQUE
#  index_terms_on_year_and_season  (year,season) UNIQUE
#
class Term < ApplicationRecord
  PENDING_DATE_UPDATES_KEY = :pending_term_date_updates

  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :trm

  has_many :courses, dependent: :destroy
  has_many :enrollments, through: :courses
  has_many :final_exams, dependent: :destroy
  has_many :university_calendar_events, dependent: :nullify

  validates :uid, presence: true, uniqueness: true

  enum :season, {
    spring: 1,
    fall: 2,
    summer: 3
  }

  # Returns active term UIDs from LeopardWeb
  # @return [Array<Integer>] UIDs of terms LeopardWeb considers active, empty array on failure
  def self.active_uids
    result = LeopardWebService.get_active_terms
    return [] unless result[:success]

    result[:terms].map { |t| t[:code].to_i }
  end

  # Returns the registration start date for this term.
  # Queries LeopardWeb to determine if registration is open for this term.
  # Once the term first appears as active, that date is considered the open date.
  # Falls back to start_date when LeopardWeb is unavailable or does not list the term.
  # @return [Date, nil] the registration start date
  def registration_start
    result = LeopardWebService.get_active_terms
    if result[:success]
      active_codes = result[:terms].map { |t| (t[:code] || t["code"]).to_i }
      if active_codes.include?(uid)
        return start_date if start_date.present? && start_date <= Time.zone.today

        return Time.zone.today
      end
    end

    start_date
  rescue => e
    Rails.logger.warn("LeopardWebService unavailable for registration_start on #{name}: #{e.message}")
    start_date
  end

  # Scope for active terms (classes have started and term hasn't ended)
  # Returns up to 3 terms if 3 are active, otherwise returns 2
  scope :active, -> {
    today = Time.zone.today

    where(start_date: ..today)
      .where(end_date: today..)
      .order(year: :desc, season: :desc)
  }

  scope :current_and_future, -> {
    current_term = Term.current
    return none unless current_term

    where("(year > ?) OR (year = ? AND season >= ?)",
          current_term.year, current_term.year, seasons[current_term.season])
      .order(year: :desc, season: :desc)
  }

  # Wrap bulk course-save operations to batch term date updates.
  def self.with_deferred_date_updates
    Thread.current[PENDING_DATE_UPDATES_KEY] = {}
    yield
  ensure
    pending = Thread.current[PENDING_DATE_UPDATES_KEY] || {}
    Thread.current[PENDING_DATE_UPDATES_KEY] = nil
    pending.each_value(&:update_dates_from_courses!)
  end

  def name
    "#{season.to_s.capitalize} #{year}"
  end

  # Update start_date and end_date from course data. Only considers dates in the expected year range.
  def update_dates_from_courses!
    new_start, new_end = courses
                         .where.not(start_date: nil)
                         .where.not(end_date: nil)
                         .where("EXTRACT(YEAR FROM start_date) >= ? AND EXTRACT(YEAR FROM start_date) <= ?", year - 1, year)
                         .where("EXTRACT(YEAR FROM end_date) >= ? AND EXTRACT(YEAR FROM end_date) <= ?", year, year + 1)
                         .pick(Arel.sql("MIN(start_date)"), Arel.sql("MAX(end_date)"))

    return unless new_start && new_end

    update!(start_date: new_start, end_date: new_end)
  end

  def active?
    return false if start_date.nil? || end_date.nil?

    Time.zone.today.between?(start_date, end_date)
  end

  def upcoming?
    return false if start_date.nil?

    Time.zone.today < start_date
  end

  def past?
    return false if end_date.nil?

    Time.zone.today > end_date
  end

  def current_or_future?
    !past?
  end

  def self.current
    today = Time.zone.today

    expected_season = case today.month
                      when 1..5 then :spring
                      when 6..7 then :summer
                      when 8..12 then :fall
                      end

    if today.month == 12 && today.day >= 15
      spring_next_year = find_by(year: today.year + 1, season: :spring)
      return spring_next_year if spring_next_year
    end

    expected_term = find_by(year: today.year, season: expected_season)
    return expected_term if expected_term

    if expected_season == :spring
      fall_term = find_by(year: today.year - 1, season: :fall)
      return fall_term if fall_term&.active?
    end

    upcoming_term = where.not(start_date: nil)
                         .where("start_date > ?", today)
                         .where(year: today.year..)
                         .order(start_date: :asc)
                         .first
    return upcoming_term if upcoming_term

    order(year: :desc, season: :desc).first
  end

  def self.next
    current_term = current
    return nil unless current_term

    case current_term.season.to_sym
    when :fall   then find_by(year: current_term.year + 1, season: :spring)
    when :spring then find_by(year: current_term.year, season: :summer)
    when :summer then find_by(year: current_term.year, season: :fall)
    end
  end

  def self.current_uid  = current&.uid
  def self.next_uid     = self.next&.uid
  def self.find_by_uid(uid)  = find_by(uid: uid)
  def self.find_by_uid!(uid) = find_by!(uid: uid)
  def self.exists_by_uid?(uid) = exists?(uid: uid)

  def self.find_by_date(date)
    return nil unless date

    date = date.to_date if date.respond_to?(:to_date)
    where.not(start_date: nil).where.not(end_date: nil)
         .where("start_date <= ? AND end_date >= ?", date, date)
         .first
  end

  def to_param
    public_id
  end
end
