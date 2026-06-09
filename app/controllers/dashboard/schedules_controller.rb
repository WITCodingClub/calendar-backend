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

    return unless @selected_term

    enrollments = current_user
                  .enrollments
                  .where(term_id: @selected_term.id)
                  .includes(course: [
                    :faculties,
                    { meeting_times: [:event_preference, { course: :faculties }] }
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
  end
end
