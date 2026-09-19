# frozen_string_literal: true

# Builds one user's schedule for the dashboard/schedules/_calendar partial.
# The dashboard uses it for the signed-in user's own schedule and for a
# friend's schedule.
module ScheduleLoading
  extend ActiveSupport::Concern

  Schedule = Data.define(
    :terms, :selected_term, :view_mode, :today, :week_start, :month_date,
    :courses, :schedule_by_day, :no_class_dates
  )

  private

  def build_schedule_for(user)
    enrolled_terms = Term.enrolled_for(user)
    terms = enrolled_terms.current_and_future
    terms = enrolled_terms.reverse_chronological.limit(6) if terms.empty?

    selected_term = if params[:term_uid].present?
                      terms.find_by(uid: params[:term_uid])
    else
                      terms.find_by(id: Term.current&.id) || terms.first
    end

    today = Time.zone.today

    week_start = if params[:week_start].present?
                   begin
                     Date.parse(params[:week_start]).beginning_of_week(:monday)
                   rescue ArgumentError, TypeError
                     today.beginning_of_week(:monday)
                   end
    else
                   today.beginning_of_week(:monday)
    end

    month_date = if params[:month].present?
                   begin
                     Date.parse("#{params[:month]}-01").beginning_of_month
                   rescue ArgumentError, TypeError
                     today.beginning_of_month
                   end
    else
                   today.beginning_of_month
    end

    courses = selected_term ? courses_for(user, selected_term) : []

    Schedule.new(
      terms:           terms,
      selected_term:   selected_term,
      view_mode:       params[:view].presence_in(%w[list week month]) || "week",
      today:           today,
      week_start:      week_start,
      month_date:      month_date,
      courses:         courses,
      schedule_by_day: schedule_by_day(courses),
      no_class_dates:  selected_term ? no_class_dates(selected_term) : []
    )
  end

  def courses_for(user, term)
    enrollments = user
                  .enrollments
                  .where(term_id: term.id)
                  .includes(course: [
                    :faculties,
                    { meeting_times: [ :event_preference, { course: :faculties } ] }
                  ])

    # The schedule owner's preferences give the colors and titles, so a friend's
    # schedule looks the same as it does in their own calendar and the extension.
    preference_resolver = PreferenceResolver.new(user)
    template_renderer   = CalendarTemplateRenderer.new

    enrollments.map do |enrollment|
      EnrolledCourseSerializer.new(
        enrollment,
        term:                term,
        preference_resolver: preference_resolver,
        template_renderer:   template_renderer
      ).as_json.with_indifferent_access
    end
  end

  def schedule_by_day(courses)
    by_day = Hash.new { |h, k| h[k] = [] }
    courses.each do |course|
      (course[:meeting_times] || []).each do |mt|
        %w[monday tuesday wednesday thursday friday saturday sunday].each do |day|
          by_day[day] << { course: course, meeting_time: mt } if mt[day]
        end
      end
    end
    by_day
  end

  def no_class_dates(term)
    dates = []
    UniversityCalendarEvent
      .where(category: %w[holiday study_day finals])
      .where(term_id: [ term.id, nil ])
      .find_each do |event|
        s = event.start_time.to_date
        e = event.end_time&.to_date || s
        (s..e).each { |d| dates << d }
      end
    dates.uniq
  end
end
