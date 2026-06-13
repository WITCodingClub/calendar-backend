# frozen_string_literal: true

module Api
  class UserExtensionConfigController < ApiController
    # GET /api/user/extension_config
    def get
      config = current_user.user_extension_config || UserExtensionConfig.new(user: current_user)

      authorize config, :show?

      render json: {
        pub_id: config.public_id,
        military_time: config.military_time,
        default_color_lecture: config.default_color_lecture,
        default_color_lab: config.default_color_lab,
        advanced_editing: config.advanced_editing,
        sync_university_events: config.sync_university_events,
        university_event_categories: config.university_event_categories || [],
        show_historic_terms: config.show_historic_terms,
        enrolled_terms: config.enrolled_terms || [],
        available_university_event_categories: UniversityCalendarEvent::CATEGORIES.map do |category|
          {
            id: category,
            name: category.titleize,
            description: university_event_category_description(category)
          }
        end
      }, status: :ok
    rescue => e
      Rails.logger.error("Error fetching user extension config for user #{current_user.id}: #{e.message}")
      render json: { error: "Failed to fetch user extension config" }, status: :internal_server_error
    end

    # PUT /api/user/extension_config
    def set
      config = UserExtensionConfig.find_or_initialize_by(user_id: current_user.id)
      authorize config, :update?

      config.military_time = params[:military_time] unless params[:military_time].nil?
      config.advanced_editing = params[:advanced_editing] unless params[:advanced_editing].nil?

      unless params[:default_color_lecture].nil?
        witcc_color = GoogleColors.to_witcc_hex(params[:default_color_lecture])
        config.default_color_lecture = witcc_color || params[:default_color_lecture]
      end

      unless params[:default_color_lab].nil?
        witcc_color = GoogleColors.to_witcc_hex(params[:default_color_lab])
        config.default_color_lab = witcc_color || params[:default_color_lab]
      end

      config.sync_university_events = params[:sync_university_events] unless params[:sync_university_events].nil?
      config.show_historic_terms = params[:show_historic_terms] unless params[:show_historic_terms].nil?

      unless params[:enrolled_terms].nil?
        terms = Array(params[:enrolled_terms]).map { |t| t.permit(:id, :name).to_h }
        config.enrolled_terms = terms
      end

      unless params[:university_event_categories].nil?
        categories = Array(params[:university_event_categories]).map(&:to_s) & UniversityCalendarEvent::CATEGORIES
        config.university_event_categories = categories
      end

      if config.save
        render json: { pub_id: config.public_id, message: "User extension config updated successfully" }, status: :ok
      else
        render json: {
          pub_id: config.public_id,
          error: "Failed to update user extension config",
          details: config.errors.full_messages
        }, status: :unprocessable_entity
      end
    rescue => e
      Rails.logger.error("Error updating user extension config for user #{current_user.id}: #{e.message}")
      render json: { error: "Failed to update user extension config" }, status: :internal_server_error
    end

    private

    def university_event_category_description(category)
      case category
      when "holiday"       then "Official university holidays and breaks (always synced)"
      when "term_dates"    then "Semester start and end dates (classes begin/end)"
      when "registration"  then "Registration periods and enrollment dates"
      when "deadline"      then "Academic deadlines (add/drop, withdrawal, payment due)"
      when "study_day"     then "Study days (no-class days before finals)"
      when "finals"        then "Final exam schedules and exam periods"
      when "graduation"    then "Commencement ceremonies and graduation events"
      when "academic"      then "Other academic events and calendar announcements"
      when "campus_event"  then "Campus activities, concerts, and student events"
      when "meeting"       then "University meetings and administrative events"
      when "exhibit"       then "Art exhibits, displays, and gallery events"
      when "announcement"  then "Important university announcements and notices"
      else                      "Other university events"
      end
    end
  end
end
