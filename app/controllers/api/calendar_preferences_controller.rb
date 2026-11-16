# frozen_string_literal: true

module Api
  class CalendarPreferencesController < BaseController
    include PreferenceParams

    authenticate_with_token

    before_action :set_calendar_preference, only: [ :show, :update, :destroy ]

    def index
      # One query for every preference the user has, split up here, instead
      # of one query for each scope.
      preferences        = policy_scope(current_user.calendar_preferences).to_a
      global_pref        = preferences.find { |p| p.scope == "global" }
      uni_cal_pref       = preferences.find { |p| p.scope == "uni_cal_global" }
      event_type_prefs   = preferences.select { |p| p.scope == "event_type" }
      uni_cal_cat_prefs  = preferences.select { |p| p.scope == "uni_cal_category" }

      render json: {
        global:          global_pref ? CalendarPreferenceSerializer.new(global_pref).as_json : nil,
        uni_cal_global:  uni_cal_pref ? CalendarPreferenceSerializer.new(uni_cal_pref).as_json : nil,
        event_types:     event_type_prefs.index_by(&:event_type).transform_values { |p| CalendarPreferenceSerializer.new(p).as_json },
        uni_cal_categories: uni_cal_cat_prefs.index_by(&:event_type).transform_values { |p| CalendarPreferenceSerializer.new(p).as_json }
      }
    end

    def show
      authorize @calendar_preference
      render json: CalendarPreferenceSerializer.new(@calendar_preference).as_json
    end

    def update
      authorize @calendar_preference

      if @calendar_preference.update(calendar_preference_params)
        render json: CalendarPreferenceSerializer.new(@calendar_preference).as_json
      else
        render_error @calendar_preference.errors.full_messages.join(", "), status: :unprocessable_content,
                     errors: @calendar_preference.errors.full_messages
      end
    end

    def destroy
      authorize @calendar_preference
      @calendar_preference.destroy
      head :no_content
    end

    def preview
      template        = params[:template]
      meeting_time_id = params[:meeting_time_id]

      if template.blank?
        render_error "Template is required", status: :bad_request
        return
      end

      if meeting_time_id.blank?
        render_error "meeting_time_id is required", status: :bad_request
        return
      end

      meeting_time = find_by_any_id(Course::MeetingTime.includes(course: :faculties), meeting_time_id)

      unless meeting_time
        render_error "Meeting time not found", status: :not_found
        return
      end

      unless Course::MeetingTime.joins(course: :enrollments)
                                .where(enrollments: { user_id: current_user.id })
                                .exists?(id: meeting_time.id)
        render_error "Meeting time not found", status: :not_found
        return
      end

      begin
        render json: { rendered: Preferences::Preview.render_template(template, meeting_time), valid: true }
      rescue Preferences::TemplateRenderer::InvalidTemplateError => e
        render_error e.message, status: :unprocessable_content, valid: false
      end
    end

    private

    def set_calendar_preference
      @calendar_preference = Preferences::ScopeParam.find_or_initialize(current_user, params[:id] || params[:scope])
    end
  end
end
