# frozen_string_literal: true

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

  def self.detect_term_dates(year, season)
    term_name_alt = season.to_s.capitalize

    classes_begin = term_dates
                    .where("summary ILIKE ?", "%classes begin%")
                    .where("academic_term ILIKE ? OR summary ILIKE ?", "%#{term_name_alt}%", "%#{year}%")
                    .where(start_time: Date.new(year - 1, 7, 1)..Date.new(year + 1, 2, 1))
                    .order(:start_time).first

    term_end = where(category: %w[term_dates finals])
               .where("summary ILIKE ? OR summary ILIKE ?", "%final exam%", "%classes end%")
               .where("academic_term ILIKE ? OR summary ILIKE ?", "%#{term_name_alt}%", "%#{year}%")
               .where(start_time: Date.new(year - 1, 7, 1)..Date.new(year + 1, 7, 1))
               .order(start_time: :desc).first

    {
      start_date: classes_begin&.start_time&.to_date,
      end_date: term_end&.end_time&.to_date || term_end&.start_time&.to_date
    }
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
