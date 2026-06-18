# frozen_string_literal: true

class Dashboard::SchedulesController < Dashboard::ApplicationController
  def show
    authorize current_user, :show?

    @terms = Term.current_and_future.order(year: :desc, season: :asc)
    @terms = Term.order(year: :desc, season: :asc).limit(6) if @terms.empty?

    @selected_term = if params[:term_uid].present?
                       Term.find_by(uid: params[:term_uid])
    else
                       Term.current || @terms.first
    end

    @view_mode = params[:view].presence_in(%w[list week month]) || "week"
    @today     = Time.zone.today

    @week_start = if params[:week_start].present?
                    begin
                      Date.parse(params[:week_start]).beginning_of_week(:monday)
                    rescue ArgumentError, TypeError
                      @today.beginning_of_week(:monday)
                    end
    else
                    @today.beginning_of_week(:monday)
    end

    @month_date = if params[:month].present?
                    begin
                      Date.parse("#{params[:month]}-01").beginning_of_month
                    rescue ArgumentError, TypeError
                      @today.beginning_of_month
                    end
    else
                    @today.beginning_of_month
    end

    return unless @selected_term

    enrollments = current_user
                  .enrollments
                  .where(term_id: @selected_term.id)
                  .includes(course: [
                    :faculties,
                    { meeting_times: [ :event_preference, { course: :faculties } ] }
                  ])

    preference_resolver = PreferenceResolver.new(current_user)
    template_renderer   = CalendarTemplateRenderer.new

    @courses = enrollments.map do |enrollment|
      EnrolledCourseSerializer.new(
        enrollment,
        term:                @selected_term,
        preference_resolver: preference_resolver,
        template_renderer:   template_renderer
      ).as_json.with_indifferent_access
    end

    @schedule_by_day = Hash.new { |h, k| h[k] = [] }
    @courses.each do |course|
      (course[:meeting_times] || []).each do |mt|
        %w[monday tuesday wednesday thursday friday saturday sunday].each do |day|
          @schedule_by_day[day] << { course: course, meeting_time: mt } if mt[day]
        end
      end
    end

    @no_class_dates = []
    UniversityCalendarEvent
      .where(category: %w[holiday study_day finals])
      .where(term_id: [ @selected_term.id, nil ])
      .find_each do |event|
        s = event.start_time.to_date
        e = event.end_time&.to_date || s
        (s..e).each { |d| @no_class_dates << d }
      end
    @no_class_dates.uniq!
  end
end
