# frozen_string_literal: true

# == Schema Information
#
# Table name: university_calendar_events
# Database name: primary
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

  # Categories for event classification
  # "academic" is a catch-all for academic events that don't fit specific categories
  CATEGORIES = %w[holiday term_dates registration deadline finals graduation academic campus_event meeting exhibit announcement other].freeze

  validates :ics_uid, presence: true, uniqueness: true
  validates :summary, presence: true
  validates :start_time, presence: true
  validates :end_time, presence: true
  validates :category, inclusion: { in: CATEGORIES }, allow_blank: true

  # Serialize recurrence as JSON array (matches GoogleCalendarEvent pattern)
  serialize :recurrence, coder: JSON

  # Scopes
  scope :upcoming, -> { where(start_time: Time.current.beginning_of_day..) }
  scope :past, -> { where(start_time: ...Time.current) }
  scope :holidays, -> { where(category: "holiday") }
  scope :term_dates, -> { where(category: "term_dates") }
  scope :registration, -> { where(category: "registration") }
  scope :deadlines, -> { where(category: "deadline") }
  scope :finals, -> { where(category: "finals") }
  scope :graduation, -> { where(category: "graduation") }
  scope :academic, -> { where(category: "academic") }
  scope :campus_events, -> { where(category: "campus_event") }
  scope :for_term, ->(term) { where(term: term) }
  scope :in_date_range, ->(start_date, end_date) {
    where(start_time: start_date.beginning_of_day..end_date.end_of_day)
  }
  scope :by_categories, ->(categories) { where(category: categories) }
  scope :with_location, -> { where.not(location: [nil, ""]) }
  scope :without_location, -> { where(location: [nil, ""]) }

  # Get holidays within a date range (useful for schedule adjustments and EXDATE generation)
  # @param start_date [Date] The start of the date range
  # @param end_date [Date] The end of the date range
  # @return [ActiveRecord::Relation] Collection of holiday events in the range
  def self.holidays_between(start_date, end_date)
    holidays.in_date_range(start_date, end_date).order(:start_time)
  end

  # Get all no-class days (holidays + finals-period events like Study Day) in a date range.
  # Used for EXDATE generation so that Study Day and similar days are excluded from
  # recurring class events even when they fall within the RRULE UNTIL window.
  # @param start_date [Date] The start of the date range
  # @param end_date [Date] The end of the date range
  # @return [ActiveRecord::Relation] Collection of no-class events in the range
  def self.no_class_days_between(start_date, end_date)
    where(category: %w[holiday finals]).in_date_range(start_date, end_date).order(:start_time)
  end

  # Detect term dates from university calendar events
  #
  # Date rules:
  # - start_date: First schedule-available event for the term.
  #               If missing, estimate as 14 days before first registration-open event.
  # - end_date:   Last day of finals period for the term.
  #               Falls back to latest imported course end_date for the term
  #               when finals period events are unavailable.
  #
  # This intentionally avoids broad year-only matching so one term's events do not
  # leak into another term's date inference.
  # @param year [Integer] The academic year
  # @param season [Symbol] The season (:fall, :spring, :summer)
  # @return [Hash] Hash with :start_date and :end_date keys
  def self.detect_term_dates(year, season)
    term = Term.find_by(year: year, season: season)

    candidate_events = where(start_time: Date.new(year - 1, 1, 1).beginning_of_day..Date.new(year + 1, 12, 31).end_of_day)
    matching_events = candidate_events.select { |event| event_matches_term_for_date_detection?(event, year, season, term) }

    # Prefer explicit schedule-available events for term start.
    schedule_available_event = matching_events
                               .select { |event| schedule_available_summary?(event.summary) }
                               .min_by(&:start_time)

    # Registration-open is used only as a fallback signal when schedule-available
    # event is missing from the feed snapshot.
    registration_event = matching_events
                         .select { |event| event.category == "registration" || registration_summary?(event.summary) }
                         .min_by(&:start_time)

    estimated_schedule_available_date = registration_event&.start_time&.to_date&.-(14)

    finals_period_event = matching_events
                          .select { |event| event.category == "finals" && finals_period_summary?(event.summary) }
                          .max_by { |event| event.end_time || event.start_time }

    finals_end_date = finals_period_event&.end_time&.to_date || finals_period_event&.start_time&.to_date
    course_end_fallback = fallback_end_date_from_courses(term)

    {
      start_date: schedule_available_event&.start_time&.to_date || estimated_schedule_available_date,
      end_date: finals_end_date || course_end_fallback
    }
  end

  # Returns true when an event can be considered part of the target term for
  # date detection purposes.
  def self.event_matches_term_for_date_detection?(event, year, season, term)
    season_name = season.to_s.capitalize
    summary = event.summary.to_s
    academic_term = event.academic_term.to_s

    # If summary explicitly names a term, trust that first.
    explicit_summary_term = extract_explicit_term_from_summary(summary)
    if explicit_summary_term
      return explicit_summary_term[:season] == season.to_sym && explicit_summary_term[:year] == year
    end

    # Strongest signal: explicit DB term linkage from sync processing.
    return true if term && event.term_id == term.id

    # Next strongest signal: summary explicitly mentions season + year.
    return true if summary.match?(/\b#{Regexp.escape(season_name)}\b/i) && summary.match?(/\b#{year}\b/)

    # Weak signal: academic term only. Restrict with season-specific date windows
    # to avoid cross-year contamination.
    return false unless academic_term.match?(/\b#{Regexp.escape(season_name)}\b/i)

    event_date = event.start_time&.to_date
    return false unless event_date

    event_date.in?(term_detection_date_window(year, season))
  end

  # Extract explicit term mention like "Fall 2026" from summary text.
  # Returns nil when no explicit term/year is present.
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

  # Date windows tuned for academic term event timing (including preregistration).
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

  # Finals period events should represent actual exam days, not announcement-only
  # "schedule available" events.
  def self.finals_period_summary?(summary)
    normalized = summary.to_s
    return false if normalized.match?(/schedule\s+(available|online|release|released|posted)/i)

    normalized.match?(/final\s+exam\s+period|final\s+exams?|finals\s+week|examination\s+period|study\s+day/i)
  end

  # Fallback end date from imported course data for the same term.
  # This is used only when finals period events are not available yet.
  def self.fallback_end_date_from_courses(term)
    return nil unless term

    term.courses.where.not(start_date: nil)
        .where.not(end_date: nil)
        .where("EXTRACT(YEAR FROM start_date) >= ? AND EXTRACT(YEAR FROM start_date) <= ?", term.year - 1, term.year)
        .where("EXTRACT(YEAR FROM end_date) >= ? AND EXTRACT(YEAR FROM end_date) <= ?", term.year, term.year + 1)
        .maximum(:end_date)
  end

  # Infer category from event summary and raw event type
  # @param summary [String] The event summary/title
  # @param event_type_raw [String] The raw event type from ICS
  # @return [String] The inferred category
  def self.infer_category(summary, event_type_raw)
    summary_lower = summary.to_s.downcase
    type_lower = event_type_raw.to_s.downcase

    # 1. HOLIDAYS - highest priority
    if summary_lower.include?("holiday") ||
       ((summary_lower.include?("break") || summary_lower.include?("recess")) &&
         (summary_lower.include?("spring") || summary_lower.include?("winter") ||
          summary_lower.include?("fall") || summary_lower.include?("summer"))) ||
       summary_lower.include?("offices closed") || summary_lower.include?("university closed") ||
       summary_lower.include?("no class") || summary_lower.include?("thanksgiving") ||
       summary_lower.include?("memorial day") || summary_lower.include?("labor day") ||
       summary_lower.include?("independence day") || summary_lower.include?("martin luther king") ||
       summary_lower.include?("presidents day") || summary_lower.include?("presidents' day") ||
       summary_lower.include?("patriots day") || summary_lower.include?("patriots' day") ||
       summary_lower.include?("juneteenth") || summary_lower.include?("july 4th") ||
       summary_lower.include?("wellbeing day") || summary_lower.include?("well-being day")
      "holiday"

    # 2. TERM DATES - classes begin/end
    elsif summary_lower.include?("classes begin") || summary_lower.include?("classes end") ||
          summary_lower.include?("first day of classes") || summary_lower.include?("last day of classes") ||
          summary_lower.include?("semester begins") || summary_lower.include?("semester ends") ||
          summary_lower.include?("term begins") || summary_lower.include?("term ends")
      "term_dates"

    # 3. FINALS - exam schedules and study days (stored as "finals" so EXDATE logic works)
    elsif summary_lower.include?("study day") ||
          summary_lower.include?("final exam") || summary_lower.include?("finals week") ||
          summary_lower.include?("final week") || summary_lower.include?("exam period") ||
          summary_lower.include?("examination period")
      "finals"

    # 4. GRADUATION - commencement ceremonies
    elsif summary_lower.include?("commencement") || summary_lower.include?("graduation") ||
          summary_lower.include?("convocation") || summary_lower.include?("conferral")
      "graduation"

    # 5. REGISTRATION - enrollment periods
    elsif summary_lower.include?("registration") || summary_lower.include?("enrollment") ||
          summary_lower.include?("add/drop") || summary_lower.include?("add drop") ||
          summary_lower.include?("course selection")
      "registration"

    # 6. DEADLINES - cutoff dates
    elsif summary_lower.include?("deadline") || summary_lower.include?("last day to") ||
          summary_lower.include?("withdrawal") || summary_lower.include?("due date") ||
          summary_lower.include?("tuition due") || summary_lower.include?("payment due") ||
          summary_lower.include?("grade submission")
      "deadline"

    # 7. ACADEMIC - catch-all for academic events (calendar announcements, etc.)
    elsif type_lower.include?("calendar announcement")
      "academic"

    # 8. MEETING
    elsif type_lower.include?("meeting")
      "meeting"

    # 9. EXHIBIT
    elsif type_lower.include?("exhibit") || type_lower.include?("showcase")
      "exhibit"

    # 10. ANNOUNCEMENT (non-academic announcements)
    elsif type_lower.include?("announcement")
      "announcement"

    # 11. Default to campus_event
    else
      "campus_event"
    end
  end

  # Check if this is a term boundary event (classes begin/end)
  def term_boundary_event?
    category == "term_dates"
  end

  # Check if this is a no-class day (holiday or finals-period event, including Study Day)
  def excludes_classes?
    %w[holiday finals].include?(category)
  end

  # Format for display
  def formatted_date
    if all_day
      start_time.strftime("%B %d, %Y")
    else
      start_time.strftime("%B %d, %Y at %l:%M %p").gsub(/\s+/, " ")
    end
  end

  # Duration in hours (for non-all-day events)
  def duration_hours
    return nil if all_day

    ((end_time - start_time) / 1.hour).round(1)
  end

  # Returns formatted summary for holiday events with school emoji prefix
  # Only appends "No Classes" if the summary doesn't already contain it
  # @return [String] The formatted holiday summary
  def formatted_holiday_summary
    # Use word boundary regex to avoid false positives like "classical" or "classroom"
    if summary.to_s.match?(/\bno\s+class(es)?\b/i)
      "🏫 #{summary}"
    else
      "🏫 #{summary} - No Classes"
    end
  end

end
