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
#  summary         :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  term_id         :bigint
#
# Indexes
#
#  index_university_calendar_events_on_academic_term            (academic_term)
#  index_university_calendar_events_on_category                 (category)
#  index_university_calendar_events_on_ics_uid                  (ics_uid) UNIQUE
#  index_university_calendar_events_on_start_time               (start_time)
#  index_university_calendar_events_on_start_time_and_end_time  (start_time,end_time)
#  index_university_calendar_events_on_term_id                  (term_id)
#
# Foreign Keys
#
#  fk_rails_...  (term_id => terms.id)
#
class UniversityCalendarEvent < ApplicationRecord
  include PublicIdentifiable

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

  # Detect term dates from university calendar events
  # Looks for "Classes Begin" and "Classes End"/"Final Exam" patterns
  # @param year [Integer] The academic year
  # @param season [Symbol] The season (:fall, :spring, :summer)
  # @return [Hash] Hash with :start_date and :end_date keys
  def self.detect_term_dates(year, season)
    term_name = "#{season.to_s.capitalize} #{year}"
    term_name_alt = season.to_s.capitalize.to_s

    # Find "Classes Begin" events (now in term_dates category)
    classes_begin = term_dates.where("summary ILIKE ?", "%classes begin%")
                              .where("academic_term ILIKE ? OR summary ILIKE ?", "%#{term_name_alt}%", "%#{year}%")
                              .where(start_time: Date.new(year - 1, 7, 1)..Date.new(year + 1, 2, 1))
                              .order(:start_time)
                              .first

    # Find term end indicators - check both term_dates and finals categories
    term_end = where(category: %w[term_dates finals])
               .where("summary ILIKE ? OR summary ILIKE ?", "%final exam%", "%classes end%")
               .where("academic_term ILIKE ? OR summary ILIKE ?", "%#{term_name_alt}%", "%#{year}%")
               .where(start_time: Date.new(year - 1, 7, 1)..Date.new(year + 1, 7, 1))
               .order(start_time: :desc)
               .first

    {
      start_date: classes_begin&.start_time&.to_date,
      end_date: term_end&.end_time&.to_date || term_end&.start_time&.to_date
    }
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
       (summary_lower.include?("break") && (summary_lower.include?("spring") || summary_lower.include?("winter") || summary_lower.include?("fall") || summary_lower.include?("summer"))) ||
       summary_lower.include?("offices closed") || summary_lower.include?("university closed") ||
       summary_lower.include?("no class") || summary_lower.include?("thanksgiving") ||
       summary_lower.include?("memorial day") || summary_lower.include?("labor day") ||
       summary_lower.include?("independence day") || summary_lower.include?("martin luther king") ||
       summary_lower.include?("presidents day") || summary_lower.include?("patriots day") ||
       summary_lower.include?("juneteenth") || summary_lower.include?("july 4th") ||
       summary_lower.include?("wellbeing day")
      "holiday"

    # 2. TERM DATES - classes begin/end
    elsif summary_lower.include?("classes begin") || summary_lower.include?("classes end") ||
          summary_lower.include?("first day of classes") || summary_lower.include?("last day of classes") ||
          summary_lower.include?("semester begins") || summary_lower.include?("semester ends") ||
          summary_lower.include?("term begins") || summary_lower.include?("term ends")
      "term_dates"

    # 3. FINALS - exam schedules (check before registration to catch "final exam")
    elsif summary_lower.include?("final exam") || summary_lower.include?("finals week") ||
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

  # Check if this is a holiday that should exclude class meetings
  def excludes_classes?
    category == "holiday"
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
