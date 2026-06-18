# frozen_string_literal: true

# == Schema Information
#
# Table name: university_calendar_events
#
#  id              :bigint           not null, primary key
#  academic_term   :string
#  all_day         :boolean          default(FALSE), not null
#  category        :string
#  description     :text
#  end_time        :datetime         not null
#  event_type_raw  :string
#  ics_uid         :string           not null
#  last_fetched_at :datetime
#  location        :string
#  organization    :string
#  recurrence      :text
#  source_url      :string
#  start_time      :datetime         not null
#  summary         :text             not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  term_id         :bigint
#
# Indexes
#
#  index_university_calendar_events_on_academic_term            (academic_term)
#  index_university_calendar_events_on_category                 (category)
#  index_university_calendar_events_on_ics_uid                  (ics_uid) UNIQUE
#  index_university_calendar_events_on_start_time_and_end_time  (start_time,end_time)
#  index_university_calendar_events_on_term_id                  (term_id)
#
# Foreign Keys
#
#  fk_rails_...  (term_id => terms.id)
#
class UniversityCalendarEvent < ApplicationRecord
  include EncodedIds::HashidIdentifiable
  include FuzzyDuplicateDetector

  set_public_id_prefix :uce, min_hash_length: 12

  belongs_to :term, optional: true
  has_many :google_calendar_events, dependent: :nullify

  CATEGORIES = %w[holiday term_dates registration deadline study_day finals graduation academic campus_event meeting exhibit announcement other].freeze

  validates :ics_uid, presence: true, uniqueness: true
  validates :summary, presence: true
  validates :start_time, :end_time, presence: true
  validates :category, inclusion: { in: CATEGORIES }, allow_blank: true

  serialize :recurrence, coder: JSON

  scope :upcoming,      -> { where(start_time: Time.current.beginning_of_day..) }
  scope :past,          -> { where(start_time: ...Time.current) }
  scope :holidays,      -> { where(category: "holiday") }
  scope :term_dates,    -> { where(category: "term_dates") }
  scope :registration,  -> { where(category: "registration") }
  scope :deadlines,     -> { where(category: "deadline") }
  scope :study_days,    -> { where(category: "study_day") }
  scope :finals,        -> { where(category: "finals") }
  scope :graduation,    -> { where(category: "graduation") }
  scope :academic,      -> { where(category: "academic") }
  scope :campus_events, -> { where(category: "campus_event") }
  scope :for_term,      ->(term) { where(term: term) }
  scope :with_location, -> { where.not(location: [ nil, "" ]) }
  scope :by_categories, ->(cats) { where(category: cats) }
  scope :in_date_range, ->(s, e) { where(start_time: s.beginning_of_day..e.end_of_day) }

  def self.holidays_between(start_date, end_date)
    holidays.in_date_range(start_date, end_date).order(:start_time)
  end

  def self.no_class_days_between(start_date, end_date)
    where(category: %w[holiday study_day finals]).in_date_range(start_date, end_date).order(:start_time)
  end

  # Detect term dates for a term.
  #
  # Date rules:
  # - start_date: The day LeopardWeb reports registration open for the term.
  #               Once captured, keep the stored past start_date stable across
  #               later syncs.
  # - end_date:   Last day of finals period for the term.
  #               Falls back to latest imported course end_date for the term
  #               when finals period events are unavailable.
  #
  # @param year [Integer] The academic year
  # @param season [Symbol] The season (:fall, :spring, :summer)
  # @return [Hash] Hash with :start_date and :end_date keys
  def self.detect_term_dates(year, season)
    term = Term.find_by(year: year, season: season)

    candidate_events = where(start_time: Date.new(year - 1, 1, 1).beginning_of_day..Date.new(year + 1, 12, 31).end_of_day)
    matching_events = candidate_events.select { |event| event_matches_term_for_date_detection?(event, year, season, term) }

    leopard_web_start_date = leopard_web_registration_open_date(year, season, term)

    schedule_available_event = matching_events
                               .select { |event| schedule_available_summary?(event.summary) }
                               .min_by(&:start_time)

    estimated_schedule_available_date = registration_event&.start_time&.to_date&.-(14)

    finals_period_event = matching_events
                          .select { |event| event.category == "finals" && finals_period_summary?(event.summary) }
                          .max_by { |event| event.end_time || event.start_time }

    finals_end_date = finals_period_event&.end_time&.to_date || finals_period_event&.start_time&.to_date
    course_end_fallback = fallback_end_date_from_courses(term)

    {
      start_date: leopard_web_start_date || schedule_available_event&.start_time&.to_date || estimated_schedule_available_date,
      end_date: finals_end_date || course_end_fallback
    }
  end

  def self.leopard_web_registration_open_date(year, season, term)
    result = LeopardWebService.get_active_terms
    return nil unless result[:success]

    target_uid = term&.uid || generated_term_uid(year, season)
    return nil unless target_uid

    active_term_found = Array(result[:terms]).any? do |active_term|
      (active_term[:code] || active_term["code"]).to_i == target_uid
    end
    return nil unless active_term_found

    existing_start_date = term&.start_date
    return existing_start_date if existing_start_date.present? && existing_start_date <= Time.zone.today

    Time.zone.today
  rescue => e
    Rails.logger.warn("Failed to determine LeopardWeb registration-open date for #{season} #{year}: #{e.message}")
    nil
  end

  def self.generated_term_uid(year, season)
    case season.to_sym
    when :fall
      ((year + 1) * 100) + 10
    when :spring
      (year * 100) + 20
    when :summer
      (year * 100) + 30
    end
  end

  def self.event_matches_term_for_date_detection?(event, year, season, term)
    season_name = season.to_s.capitalize
    summary = event.summary.to_s
    academic_term = event.academic_term.to_s

    explicit_summary_term = extract_explicit_term_from_summary(summary)
    if explicit_summary_term
      return explicit_summary_term[:season] == season.to_sym && explicit_summary_term[:year] == year
    end

    return true if term && event.term_id == term.id
    return true if summary.match?(/\b#{Regexp.escape(season_name)}\b/i) && summary.match?(/\b#{year}\b/)

    return false unless academic_term.match?(/\b#{Regexp.escape(season_name)}\b/i)

    event_date = event.start_time&.to_date
    return false unless event_date

    event_date.in?(term_detection_date_window(year, season))
  end

  def self.extract_explicit_term_from_summary(summary)
    match = summary.to_s.match(/\b(Fall|Spring|Summer)\s+(\d{4})\b/i)
    return nil unless match

    season = case match[1].downcase
    when "fall" then :fall
    when "spring" then :spring
    when "summer" then :summer
    end

    return nil unless season

    { season: season, year: match[2].to_i }
  end

  def self.term_detection_date_window(year, season)
    case season.to_sym
    when :spring
      Date.new(year - 1, 8, 1)..Date.new(year, 6, 30)
    when :summer
      Date.new(year, 1, 1)..Date.new(year, 8, 31)
    when :fall
      Date.new(year, 1, 1)..Date.new(year, 12, 31)
    else
      Date.new(year - 1, 1, 1)..Date.new(year + 1, 12, 31)
    end
  end

  def self.schedule_available_summary?(summary)
    normalized = summary.to_s
    return false if registration_summary?(normalized)

    normalized.match?(/course\s+schedule/i) ||
      normalized.match?(/schedule\s+(available|release|released|posted|opens|open|begins|begin)/i)
  end

  def self.registration_summary?(summary)
    summary.to_s.match?(/registration\s+(opens|open|begins|begin)|registration/i)
  end

  def self.finals_period_summary?(summary)
    normalized = summary.to_s
    return false if normalized.match?(/schedule\s+(available|online|release|released|posted)/i)

    normalized.match?(/final\s+exam\s+period|final\s+exams?|finals\s+week|examination\s+period|study\s+day/i)
  end

  def self.fallback_end_date_from_courses(term)
    return nil unless term

    term.courses.where.not(start_date: nil)
        .where.not(end_date: nil)
        .where("EXTRACT(YEAR FROM start_date) >= ? AND EXTRACT(YEAR FROM start_date) <= ?", term.year - 1, term.year)
        .where("EXTRACT(YEAR FROM end_date) >= ? AND EXTRACT(YEAR FROM end_date) <= ?", term.year, term.year + 1)
        .maximum(:end_date)
  end

  def self.infer_category(summary, event_type_raw)
    s = summary.to_s.downcase
    t = event_type_raw.to_s.downcase

    if s.include?("holiday") ||
       s.match?(/\b(spring|winter|fall|summer)\s+(break|recess)\b/) ||
       s.include?("thanksgiving") ||
       s.include?("offices closed") || s.include?("university closed") ||
       s.include?("no class") ||
       s.include?("memorial day") || s.include?("labor day") ||
       s.include?("independence day") || s.include?("july 4th") || s.include?("july 4") ||
       s.match?(/martin luther king|mlk day/i) ||
       s.include?("presidents' day") || s.include?("presidents day") ||
       s.include?("patriots' day") || s.include?("patriots day") ||
       s.include?("veterans day") || s.include?("veteran's day") ||
       s.include?("indigenous peoples") || s.include?("columbus day") ||
       s.include?("election day") ||
       s.include?("juneteenth") ||
       s.include?("wellbeing day") || s.include?("well-being day")
      "holiday"
    elsif s.include?("classes begin") || s.include?("classes end") ||
          s.include?("first day of classes") || s.include?("last day of classes") ||
          s.include?("semester begins") || s.include?("semester ends")
      "term_dates"
    elsif s.include?("study day") || s.include?("study period") ||
          s.include?("reading day") || s.include?("reading period")
      "study_day"
    elsif s.include?("final exam") || s.include?("finals week") ||
          s.include?("exam period") || s.include?("final examinations")
      "finals"
    elsif s.include?("commencement") || s.include?("graduation") || s.include?("convocation")
      "graduation"
    elsif s.include?("registration") || s.include?("enrollment") ||
          s.include?("add/drop") || s.include?("course selection")
      "registration"
    elsif s.include?("deadline") || s.include?("last day to") ||
          s.include?("withdrawal") || s.include?("tuition due") ||
          s.include?("grade submission") || s.include?("incomplete grade") ||
          s.include?("pass/fail") || s.include?("grade change")
      "deadline"
    elsif t.include?("calendar announcement") then "academic"
    elsif t.include?("meeting") then "meeting"
    elsif t.include?("exhibit") || t.include?("showcase") then "exhibit"
    elsif t.include?("announcement") then "announcement"
    else "campus_event"
    end
  end

  def term_boundary_event? = category == "term_dates"
  def excludes_classes?    = %w[holiday study_day finals].include?(category)

  def formatted_date
    all_day ? start_time.strftime("%B %d, %Y") : start_time.strftime("%B %d, %Y at %l:%M %p").squish
  end

  def duration_hours
    return nil if all_day

    ((end_time - start_time) / 1.hour).round(1)
  end

  def formatted_holiday_summary
    if summary.to_s.match?(/\bno\s+class(es)?\b/i)
      "🏫 #{summary}"
    else
      "🏫 #{summary} - No Classes"
    end
  end
end
