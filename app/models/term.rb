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
#  details_synced_at     :datetime
#  end_date              :date
#  season                :integer          not null
#  sections_synced_at    :datetime
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
# A term's dates have two sources. Its courses win: a course save writes
# start_date and end_date from the first class and the last course end
# (update_dates_from_courses!). UniversityCalendar::TermDates fills a date
# that is still empty, from LeopardWeb and the university calendar, for a
# term that has no courses yet.
class Term < ApplicationRecord
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :trm

  has_many :courses, dependent: :destroy
  has_many :enrollments, through: :courses
  has_many :final_exams, dependent: :destroy
  has_many :term_processing_statuses, dependent: :delete_all
  has_many :term_elective_lists, dependent: :destroy
  has_many :university_calendar_events, dependent: :nullify
  has_many :friend_meetings, dependent: :nullify

  validates :uid, presence: true, uniqueness: true

  enum :season, {
    spring: 1,
    fall: 2,
    summer: 3
  }

  # The uid is the Banner code (TermCode), and the codes sort in time order.
  # The season column does not: fall is 2 and summer 3.
  scope :chronological, -> { order(:uid) }
  scope :reverse_chronological, -> { order(uid: :desc) }

  scope :enrolled_for, ->(user) { where(id: Enrollment.where(user: user).select(:term_id)) }

  # The terms in session today: classes have started and the term has not ended.
  scope :active, -> {
    today = Time.zone.today

    where(start_date: ..today)
      .where(end_date: today..)
      .reverse_chronological
  }

  scope :current_and_future, ->(current_term = Term.current) {
    return none unless current_term

    where(uid: current_term.uid..).reverse_chronological
  }

  # Inside the block, a course save marks its term, and each term updates its
  # dates one time when the block ends.
  def self.with_deferred_date_updates
    Current.deferred_term_dates = {}
    yield
  ensure
    pending = Current.deferred_term_dates || {}
    Current.deferred_term_dates = nil
    pending.each_value(&:update_dates_from_courses!)
  end

  def name
    "#{season.to_s.capitalize} #{year}"
  end

  # A section of the term starts in the term's year or the year before, and
  # ends in the term's year or the year after. Banner has sections with
  # dates of another term, and the importer and the term dates skip them.
  def section_dates?(start_date, end_date)
    section_start_dates.cover?(start_date) && section_end_dates.cover?(end_date)
  end

  def section_start_dates = Date.new(year - 1, 1, 1)..Date.new(year, 12, 31)
  def section_end_dates = Date.new(year, 1, 1)..Date.new(year + 1, 12, 31)

  # The first start and the last end of the term's sections, or nil when no
  # section has dates in the term's years.
  def course_dates
    first, last = courses.where(start_date: section_start_dates, end_date: section_end_dates)
                         .pick(Arel.sql("MIN(start_date)"), Arel.sql("MAX(end_date)"))
    [ first, last ] if first && last
  end

  def update_dates_from_courses!
    first, last = course_dates
    update!(start_date: first, end_date: last) if first
  end

  def course_dates_changed!
    if (pending = Current.deferred_term_dates)
      pending[id] ||= self
    else
      update_dates_from_courses!
    end
  end

  # The dates a term can have. Before its courses give dates, start_date is
  # the day the schedule or registration opens, so a spring term can start in
  # the fall before it. Classes end in the term's own year.
  def self.date_window(year, season)
    case season.to_sym
    when :spring then Date.new(year - 1, 8, 1)..Date.new(year, 6, 30)
    when :summer then Date.new(year, 1, 1)..Date.new(year, 8, 31)
    when :fall   then Date.new(year, 1, 1)..Date.new(year, 12, 31)
    else Date.new(year - 1, 1, 1)..Date.new(year + 1, 12, 31)
    end
  end

  # Classes end in the term's own year for every season.
  def self.plausible_end_date?(date, year, window = nil)
    return false if date.nil? || date.year != year

    window.nil? || date.in?(window)
  end

  def date_window = self.class.date_window(year, season)

  # The date columns that fall outside date_window, for lib/tasks/term_dates.rake.
  def implausible_date_fields
    fields = []
    fields << :start_date if start_date && !start_date.in?(date_window)
    fields << :end_date if end_date && !self.class.plausible_end_date?(end_date, year, date_window)
    fields
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

  # True when the term has final exams and a finals schedule upload finished.
  # The parser saves one exam at a time, so during the first import (or after
  # a failed one) the term has only some of its exams. Terms from the old
  # backend have exams and no FinalsSchedule.
  def finals_published?
    return false unless final_exams.exists?

    schedules = FinalsSchedule.for_term(self)
    !schedules.exists? || schedules.completed.exists?
  end

  # Term.current keeps its id in Rails.cache under a key for the date, and
  # memoizes the record for the request in Current. A commit on any term clears
  # both. The TTL covers writes that skip callbacks, such as insert_all!.
  CURRENT_ID_CACHE_TTL = 5.minutes

  after_commit { self.class.expire_current_cache }

  def self.current
    today = Time.zone.today

    Current.terms.fetch(today) do
      id = Rails.cache.fetch(current_id_cache_key(today), expires_in: CURRENT_ID_CACHE_TTL) { find_current(today)&.id }
      Current.terms[today] = id && find_by(id: id)
    end
  end

  def self.current_id_cache_key(date)
    "term:current_id:#{date.iso8601}"
  end

  def self.expire_current_cache
    Rails.cache.delete(current_id_cache_key(Time.zone.today))
    Current.terms = {}
  end

  def self.find_current(today)
    expected = TermCode.for_date(today)

    if today.month == 12 && today.day >= 15
      spring_next_year = find_by(uid: TermCode.next_term(expected))
      return spring_next_year if spring_next_year
    end

    expected_term = find_by(uid: expected)
    return expected_term if expected_term

    if TermCode.season(expected) == "spring"
      fall_term = find_by(uid: TermCode.for(today.year - 1, "fall"))
      return fall_term if fall_term&.active?
    end

    upcoming_term = where.not(start_date: nil)
                         .where("start_date > ?", today)
                         .where(year: today.year..)
                         .order(start_date: :asc)
                         .first
    return upcoming_term if upcoming_term

    reverse_chronological.first
  end

  # Pass the current term when the caller already has it. Term.current sends
  # up to six queries, so the API and the dashboard ask for it only once.
  def self.next(current_term = current)
    current_term && find_by(uid: TermCode.next_term(current_term.uid))
  end

  def self.current_uid  = current&.uid
  def self.next_uid     = self.next&.uid

  # The term with this uid. find_by! would put its SQL in the message, and
  # the API and the MCP tools show the message to the client.
  def self.find_by_uid!(uid)
    find_by(uid: uid) || raise(ActiveRecord::RecordNotFound.new("No term #{uid}", name, "uid", uid))
  end

  # The terms that Catalog::CourseDataSyncJob reads from Banner each night:
  # the terms in session and every term from the current one on. Rooms and
  # times only move for those. Banner lists every term back to 2014, about
  # 118,000 Banner requests a night, nearly all for terms that ended years ago.
  def self.synced_uids
    (active.pluck(:uid) + current_and_future.pluck(:uid)).uniq
  end

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
