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
  has_many :calendar_events, dependent: :nullify

  # Every category the importer can store. Admins can see and filter events in all of them.
  CATEGORIES = %w[holiday term_dates registration deadline study_day finals graduation academic campus_event meeting exhibit announcement other].freeze

  # The categories a person can sync. The feed puts too much clutter in campus_event,
  # meeting, exhibit, announcement, and other, so they stay in the database but never
  # sync (issue #621).
  SYNCABLE_CATEGORIES = %w[holiday term_dates registration deadline study_day finals graduation academic].freeze

  # Shown to users who pick which categories to sync, in the extension and on the dashboard.
  CATEGORY_DESCRIPTIONS = {
    "holiday"      => "Official university holidays and breaks (always synced)",
    "term_dates"   => "Semester start and end dates (classes begin/end)",
    "registration" => "Registration periods and enrollment dates",
    "deadline"     => "Academic deadlines (add/drop, withdrawal, payment due)",
    "study_day"    => "Study days (no-class days before finals)",
    "finals"       => "Final exam schedules and exam periods",
    "graduation"   => "Commencement ceremonies and graduation events",
    "academic"     => "Other academic events and calendar announcements"
  }.freeze

  def self.category_description(category)
    CATEGORY_DESCRIPTIONS.fetch(category.to_s, "Other university events")
  end

  # Categories of the events that cancel classes on their dates.
  NO_CLASS_CATEGORIES = %w[holiday study_day finals].freeze

  # The cache holds plain times, not records, so a schema change cannot break
  # an entry. The TTL covers writes that skip callbacks.
  NO_CLASS_SPANS_CACHE_KEY = "university_calendar_events:no_class_spans"
  NO_CLASS_SPANS_CACHE_TTL = 1.hour

  # The dates of one no-class event, from no_class_spans_between. The ICS feed
  # reads updated_at for the LAST-MODIFIED of a class event.
  NoClassSpan = Data.define(:start_time, :end_time, :updated_at)

  after_commit { self.class.expire_no_class_spans_cache }

  validates :ics_uid, presence: true, uniqueness: true
  validates :summary, presence: true
  validates :start_time, :end_time, presence: true
  validates :category, inclusion: { in: CATEGORIES }, allow_blank: true

  serialize :recurrence, coder: JSON

  scope :upcoming,      -> { where(start_time: Time.current.beginning_of_day..) }
  scope :past,          -> { where(start_time: ...Time.current) }
  scope :holidays,      -> { where(category: "holiday") }
  scope :finals,        -> { where(category: "finals") }
  scope :for_term,      ->(term) { where(term: term) }
  scope :with_location, -> { where.not(location: [ nil, "" ]) }
  scope :by_categories, ->(cats) { where(category: cats) }
  # Events that overlap the range. A break is one event of several days, so an
  # event that starts before the range still counts when it runs into it.
  scope :in_date_range, ->(s, e) { where(end_time: s.beginning_of_day.., start_time: ..e.end_of_day) }

  def self.holidays_between(start_date, end_date)
    holidays.in_date_range(start_date, end_date).order(:start_time)
  end

  # The no-class spans that overlap the range, earliest first. They come from
  # Rails.cache, so a schedule, an ICS feed, or a sync does not query the table.
  # The match is the same as in_date_range.
  def self.no_class_spans_between(start_date, end_date)
    range_start = start_date.beginning_of_day
    range_end   = end_date.end_of_day

    cached_no_class_spans.filter_map do |start_time, end_time, updated_at|
      NoClassSpan.new(start_time:, end_time:, updated_at:) if end_time >= range_start && start_time <= range_end
    end
  end

  # The start, end, and updated_at of every no-class event. There are few of them, so one
  # cache entry holds them all. A commit on any event clears it.
  def self.cached_no_class_spans
    Rails.cache.fetch(NO_CLASS_SPANS_CACHE_KEY, expires_in: NO_CLASS_SPANS_CACHE_TTL) do
      where(category: NO_CLASS_CATEGORIES).order(:start_time).pluck(:start_time, :end_time, :updated_at)
    end
  end

  def self.expire_no_class_spans_cache
    Rails.cache.delete(NO_CLASS_SPANS_CACHE_KEY)
  end

  # Every date inside the range that a holiday, study day, or finals event covers.
  def self.no_class_dates_between(start_date, end_date)
    no_class_spans_between(start_date, end_date).flat_map do |span|
      first = span.start_time.in_time_zone.to_date
      last  = [ span.end_time.in_time_zone.to_date, first ].max
      ([ first, start_date.to_date ].max..[ last, end_date.to_date ].min).to_a
    end.uniq
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

  def excludes_classes?    = NO_CLASS_CATEGORIES.include?(category)

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
