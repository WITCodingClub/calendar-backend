# frozen_string_literal: true

class CalendarsController < ApplicationController
  include ApplicationHelper

  skip_before_action :verify_authenticity_token

  def show
    @user = User.find_by!(calendar_token: params[:calendar_token])

    @courses = @user.courses
                    .includes(:term, meeting_times: [ { rooms: :building }, { course: [ :faculties, :term ] } ])

    @final_exams = FinalExam.where(course_id: @courses.pluck(:id))
                            .where(exam_date: Time.zone.today..)
                            .includes(:course)

    respond_to do |format|
      format.ics do
        calendar = generate_ical(@courses, @final_exams)

        response.headers["Cache-Control"]      = "max-age=3600, must-revalidate"
        response.headers["X-Published-TTL"]    = "PT1H"
        response.headers["Refresh-Interval"]   = "3600"

        render plain: calendar.to_ical, content_type: "text/calendar"
      end
    end
  end

  private

  def generate_ical(courses, final_exams)
    require "icalendar"

    @preference_resolver   = PreferenceResolver.new(@user)
    @template_renderer     = CalendarTemplateRenderer.new
    @holidays_cache        = preload_holidays_cache(courses)
    @ics_course_finals_cache       = {}
    @ics_term_finals_cache         = {}
    @ics_term_finals_period_cache  = {}

    cal = Icalendar::Calendar.new
    cal.prodid = "-//WITCC//Course Calendar//EN"
    cal.append_custom_property("X-WR-CALNAME", "WIT Course Schedule")
    cal.append_custom_property("X-WR-CALDESC", "WIT Course Schedule Calendar for #{@user.full_name}")

    cal.timezone do |t|
      t.tzid = "America/New_York"
      t.daylight do |d|
        d.tzoffsetfrom = "-0500"
        d.tzoffsetto   = "-0400"
        d.tzname       = "EDT"
        d.dtstart      = "19700308T020000"
        d.rrule        = "FREQ=YEARLY;BYMONTH=3;BYDAY=2SU"
      end
      t.standard do |s|
        s.tzoffsetfrom = "-0400"
        s.tzoffsetto   = "-0500"
        s.tzname       = "EST"
        s.dtstart      = "19701101T020000"
        s.rrule        = "FREQ=YEARLY;BYMONTH=11;BYDAY=1SU"
      end
    end

    courses.each do |course|
      filtered_meeting_times = course.meeting_times
                                     .group_by { |mt| [ mt.day_of_week, mt.begin_time, mt.end_time ] }
                                     .map do |_key, group|
                                       non_tbd = group.reject { |mt| LocationHelper.tbd_building?(mt.building) || mt.rooms.all? { |r| LocationHelper.tbd_room?(r) } }
                                       non_tbd.any? ? non_tbd.first : group.first
                                     end

      filtered_meeting_times.each do |meeting_time|
        next if meeting_time.day_of_week.blank?

        cal.event do |e|
          first_meeting_date = find_first_meeting_date(meeting_time)
          next unless first_meeting_date

          start_time = parse_time(first_meeting_date, meeting_time.begin_time)
          end_time   = parse_time(first_meeting_date, meeting_time.end_time)

          if meeting_time.all_day?
            e.dtstart = Icalendar::Values::Date.new(first_meeting_date)
            e.dtend   = Icalendar::Values::Date.new(first_meeting_date + 1.day)
          else
            e.dtstart = Icalendar::Values::DateTime.new(start_time, tzid: "America/New_York")
            e.dtend   = Icalendar::Values::DateTime.new(end_time,   tzid: "America/New_York")
          end

          prefs   = @preference_resolver.resolve_for(meeting_time)
          context = CalendarTemplateRenderer.build_context_from_meeting_time(meeting_time)

          e.summary = if prefs[:title_template].present?
                        @template_renderer.render(prefs[:title_template], context)
          else
                        titleize_with_roman_numerals(course.title)
          end

          e.description = @template_renderer.render(prefs[:description_template], context) if prefs[:description_template].present?

          non_tbd_rooms = meeting_time.rooms.reject { |r| LocationHelper.tbd_room?(r) }
          if non_tbd_rooms.any? && meeting_time.building &&
             !LocationHelper.tbd_building?(meeting_time.building)
            e.location = "#{meeting_time.building.name} - #{non_tbd_rooms.map(&:formatted_number).join(' / ')}"
          elsif non_tbd_rooms.any?
            e.location = non_tbd_rooms.map(&:formatted_number).join(" / ")
          elsif LocationHelper.tbd_building?(meeting_time.building) || LocationHelper.tbd_room?(meeting_time.room)
            e.location = "TBD"
          end

          recurrence_end = ics_recurrence_end_for(meeting_time, course)
          day_sym        = meeting_time.day_of_week.to_sym

          if meeting_time.all_day?
            until_time = Time.utc(recurrence_end.year, recurrence_end.month, recurrence_end.day)
            rule        = IceCube::Rule.weekly.day(day_sym).until(until_time)
            e.rrule     = rule.to_ical.gsub(/UNTIL=(\d{8})T\d{6}Z?/, 'UNTIL=\1')
          else
            # End-of-day in local (Eastern) zone as UTC, so evening classes keep
            # their final occurrence instead of it falling past a bare-UTC UNTIL.
            until_time = Time.zone.local(recurrence_end.year, recurrence_end.month, recurrence_end.day, 23, 59, 59).utc
            rule        = IceCube::Rule.weekly.day(day_sym).until(until_time)
            e.rrule     = rule.to_ical
          end

          build_holiday_exdates_for_meeting_time(meeting_time, start_time).each do |exdate|
            if meeting_time.all_day?
              e.append_exdate(Icalendar::Values::Date.new(exdate.to_date))
            else
              e.append_exdate(Icalendar::Values::DateTime.new(exdate, tzid: "America/New_York"))
            end
          end

          e.uid = "course-#{course.crn}-meeting-#{meeting_time.id}@calendar-util.wit.edu"

          color_hex = if prefs[:color_id].present?
                        get_google_color_hex(prefs[:color_id])
          elsif meeting_time.event_color.present?
                        meeting_time.event_color
          end

          if color_hex
            e.color = "##{color_hex}"
            e.append_custom_property("X-APPLE-CALENDAR-COLOR", "##{color_hex}")
            e.append_custom_property("COLOR", color_hex.to_s)
          end

          e.dtstamp = Icalendar::Values::DateTime.new(Time.current, tzid: "America/New_York")

          last_modified = [ course.updated_at, meeting_time.updated_at ].max
          e.last_modified = Icalendar::Values::DateTime.new(last_modified, tzid: "America/New_York")
          e.sequence      = (last_modified.to_i / 60)
        end
      end
    end

    add_final_exam_events(cal, final_exams)
    add_university_events(cal)

    cal
  end

  def add_final_exam_events(cal, final_exams)
    final_exams.each do |final_exam|
      next unless final_exam.start_datetime && final_exam.end_datetime

      cal.event do |e|
        e.dtstart     = Icalendar::Values::DateTime.new(final_exam.start_datetime, tzid: "America/New_York")
        e.dtend       = Icalendar::Values::DateTime.new(final_exam.end_datetime,   tzid: "America/New_York")
        e.summary     = "Final Exam: #{titleize_with_roman_numerals(final_exam.course_title)}"
        e.description = final_exam.course_code
        e.location    = final_exam.location_with_names if final_exam.location.present?
        e.uid         = "final-exam-#{final_exam.id}@calendar-util.wit.edu"
        e.dtstamp     = Icalendar::Values::DateTime.new(Time.current, tzid: "America/New_York")
        e.last_modified = Icalendar::Values::DateTime.new(final_exam.updated_at, tzid: "America/New_York")
        e.sequence    = (final_exam.updated_at.to_i / 60)
      end
    end
  end

  def add_university_events(cal)
    enrolled_term_ids = @courses.map(&:term_id).compact.uniq
    return if enrolled_term_ids.empty?

    min_date, max_date = holiday_date_range_for_terms(enrolled_term_ids)
    if min_date && max_date
      UniversityCalendarEvent.holidays.in_date_range(min_date, max_date).find_each do |event|
        add_university_event_to_calendar(cal, event, force_all_day: true)
      end
    end

    user_config = @user.user_extension_config
    return unless user_config&.sync_university_events

    categories = (user_config.university_event_categories || []) - [ "holiday" ]
    return if categories.empty?

    if min_date && max_date
      UniversityCalendarEvent.by_categories(categories).in_date_range(min_date, max_date).find_each do |event|
        add_university_event_to_calendar(cal, event)
      end
    end
  end

  # Returns [min_date, max_date] for the holiday query range.
  # Prefers term start/end dates; falls back to meeting time dates when terms
  # lack end_date (e.g. Fall 2026 before finals are scheduled).
  def holiday_date_range_for_terms(enrolled_term_ids)
    terms = Term.where(id: enrolled_term_ids).where.not(start_date: nil).where.not(end_date: nil)
    if terms.any?
      return [ terms.minimum(:start_date), terms.maximum(:end_date) ]
    end

    meeting_times = @courses.flat_map { |c| c.meeting_times.to_a }
    min = meeting_times.filter_map(&:start_date).min
    max = meeting_times.filter_map(&:end_date).max
    [ min, max ]
  end

  def add_university_event_to_calendar(cal, event, force_all_day: false)
    cal.event do |e|
      is_all_day = force_all_day || event.all_day || event.category == "holiday"

      if is_all_day
        e.dtstart = Icalendar::Values::Date.new(event.start_time.to_date)
        e.dtend   = Icalendar::Values::Date.new(event.end_time.to_date + 1.day)
      else
        e.dtstart = Icalendar::Values::DateTime.new(event.start_time, tzid: "America/New_York")
        e.dtend   = Icalendar::Values::DateTime.new(event.end_time,   tzid: "America/New_York")
      end

      e.summary     = event.category == "holiday" ? event.formatted_holiday_summary : event.summary
      e.description = event.description if event.description.present?
      e.location    = event.location    if event.location.present?
      e.uid         = "university-#{event.ics_uid}@calendar-util.wit.edu"
      e.dtstamp     = Icalendar::Values::DateTime.new(Time.current,    tzid: "America/New_York")
      e.last_modified = Icalendar::Values::DateTime.new(event.updated_at, tzid: "America/New_York")
      e.sequence    = (event.updated_at.to_i / 60)
      e.categories  = [ event.category.titleize ] if event.category.present?

      if event.category == "holiday"
        e.append_custom_property("X-MICROSOFT-CDO-ALLDAYEVENT", "TRUE")
        e.append_custom_property("X-MICROSOFT-CDO-BUSYSTATUS", "FREE")
        e.transp = "TRANSPARENT"
      end
    end
  end

  def preload_holidays_cache(courses)
    meeting_times = courses.flat_map { |c| c.meeting_times.to_a }
    return {} if meeting_times.empty?

    min_date = meeting_times.filter_map(&:start_date).min
    max_date = meeting_times.filter_map(&:end_date).max
    return {} unless min_date && max_date

    all_no_class_days = UniversityCalendarEvent.no_class_days_between(min_date, max_date).to_a

    meeting_times.map { |mt| [ mt.start_date, mt.end_date ] }.uniq.each_with_object({}) do |(start_date, end_date), cache|
      cache[[ start_date, end_date ]] = all_no_class_days.select do |h|
        h.start_time.to_date <= end_date && h.end_time.to_date >= start_date
      end
    end
  end

  def build_holiday_exdates_for_meeting_time(meeting_time, start_time)
    target_wday = Course::MeetingTime.day_of_weeks[meeting_time.day_of_week]
    return [] if target_wday.nil?

    cache_key = [ meeting_time.start_date, meeting_time.end_date ]
    holidays  = @holidays_cache[cache_key] ||= UniversityCalendarEvent.no_class_days_between(
      meeting_time.start_date,
      meeting_time.end_date
    ).to_a

    exdates = []

    holidays.each do |holiday|
      is_multi_day = holiday.end_time && holiday.start_time.to_date != holiday.end_time.to_date

      if is_multi_day
        (holiday.start_time.to_date..holiday.end_time.to_date).each do |date|
          next unless date.wday == target_wday

          exdates << Time.zone.local(date.year, date.month, date.day, start_time.hour, start_time.min, 0)
        end
      elsif holiday.start_time.wday == target_wday
        exdates << Time.zone.local(
          holiday.start_time.year, holiday.start_time.month, holiday.start_time.day,
          start_time.hour, start_time.min, 0
        )
      end
    end

    exdates
  end

  def ics_recurrence_end_for(meeting_time, course)
    recurrence_end = meeting_time.end_date.to_date

    course_final = ics_final_exam_date_for_course(course.id)
    if course_final && course_final < recurrence_end
      recurrence_end = course_final - 1.day
    else
      term_finals_start = ics_earliest_final_for_term(course.term_id)
      if term_finals_start && term_finals_start < recurrence_end
        recurrence_end = term_finals_start - 1.day
      end
    end

    study_day = ics_earliest_finals_period_for_term(course.term_id)
    if study_day && (study_day - 1.day) < recurrence_end
      recurrence_end = study_day - 1.day
    end

    recurrence_end
  end

  def ics_final_exam_date_for_course(course_id)
    return @ics_course_finals_cache[course_id] if @ics_course_finals_cache.key?(course_id)

    @ics_course_finals_cache[course_id] = FinalExam.where(course_id: course_id)
                                                   .where.not(exam_date: nil)
                                                   .minimum(:exam_date)
  end

  def ics_earliest_final_for_term(term_id)
    return @ics_term_finals_cache[term_id] if @ics_term_finals_cache.key?(term_id)

    @ics_term_finals_cache[term_id] = FinalExam.where(term_id: term_id)
                                               .where.not(exam_date: nil)
                                               .minimum(:exam_date)
  end

  def ics_earliest_finals_period_for_term(term_id)
    return @ics_term_finals_period_cache[term_id] if @ics_term_finals_period_cache.key?(term_id)

    @ics_term_finals_period_cache[term_id] = UniversityCalendarEvent
                                             .where(term_id: term_id, category: "finals")
                                             .where("summary ILIKE ? OR summary ILIKE ?", "%Final Exam Period%", "%Study Day%")
                                             .minimum(:start_time)
                                             &.to_date
  end

  def parse_time(date, time_int)
    return nil unless date && time_int

    hours   = time_int / 100
    minutes = time_int % 100
    Time.zone.local(date.year, date.month, date.day, hours, minutes)
  end

  def find_first_meeting_date(meeting_time)
    return nil if meeting_time.day_of_week.blank?

    target_wday  = Course::MeetingTime.day_of_weeks[meeting_time.day_of_week]
    current_date = meeting_time.start_date.to_date

    7.times do
      return current_date if current_date.wday == target_wday

      current_date += 1.day
    end

    nil
  end

  def get_google_color_hex(color_id)
    {
      1 => "A4BDFC", 2 => "7AE7BF", 3 => "DBADFF", 4 => "FF887C",
      5 => "FBD75B", 6 => "FFB878", 7 => "46D6DB", 8 => "E1E1E1",
      9 => "5484ED", 10 => "51B749", 11 => "DC2127"
    }[color_id]
  end
end
