# frozen_string_literal: true

module Api
  class UserExtensionConfigController < ApiController
    def set
      config = UserExtensionConfig.find_or_initialize_by(user_id: current_user.id)
      authorize config, :update?

      config.military_time = params[:military_time] unless params[:military_time].nil?
      config.advanced_editing = params[:advanced_editing] unless params[:advanced_editing].nil?

      # Convert Google event colors to WITCC colors before storing
      unless params[:default_color_lecture].nil?
        witcc_color = GoogleColors.to_witcc_hex(params[:default_color_lecture])
        config.default_color_lecture = witcc_color || params[:default_color_lecture]
      end

      unless params[:default_color_lab].nil?
        witcc_color = GoogleColors.to_witcc_hex(params[:default_color_lab])
        config.default_color_lab = witcc_color || params[:default_color_lab]
      end

      # University calendar event preferences
      config.sync_university_events = params[:sync_university_events] unless params[:sync_university_events].nil?

      unless params[:university_event_categories].nil?
        categories = params[:university_event_categories]
        # Ensure it's an array and only contains valid categories
        categories = Array(categories).map(&:to_s) & UniversityCalendarEvent::CATEGORIES
        config.university_event_categories = categories
      end

      if config.save
        render json: {
          pub_id: config.public_id,
          message: "User extension config updated successfully"
        }, status: :ok
      else
        render json: {
          pub_id: config.public_id,
          error: "Failed to update user extension config",
          details: config.errors.full_messages }, status: :unprocessable_entity
      end
    rescue => e
      Rails.logger.error("Error updating user extension config for user #{current_user.id}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render json: { error: "Failed to update user extension config" }, status: :internal_server_error

    end

    def get
      config = current_user.user_extension_config

      if config.nil?
        render json: {
          error: "User extension config not found"
        }, status: :not_found
        return
      end

      authorize config, :show?

      # Return WITCC colors as stored in database
      render json: {
        pub_id: config.public_id,
        military_time: config.military_time,
        default_color_lecture: config.default_color_lecture,
        default_color_lab: config.default_color_lab,
        advanced_editing: config.advanced_editing,
        sync_university_events: config.sync_university_events,
        university_event_categories: config.university_event_categories || [],
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
      Rails.logger.error(e.backtrace.join("\n"))
      render json: {
        error: "Failed to fetch user extension config" }, status: :internal_server_error
    end

    private

    def university_event_category_description(category)
      case category
      when "holiday"
        "Official university holidays and breaks (always synced)"
      when "term_dates"
        "Semester start and end dates (classes begin/end)"
      when "registration"
        "Registration periods and enrollment dates"
      when "deadline"
        "Academic deadlines (add/drop, withdrawal, payment due)"
      when "finals"
        "Final exam schedules and exam periods"
      when "graduation"
        "Commencement ceremonies and graduation events"
      when "campus_event"
        "Campus activities, concerts, and student events"
      when "meeting"
        "University meetings and administrative events"
      when "exhibit"
        "Art exhibits, displays, and gallery events"
      when "announcement"
        "Important university announcements and notices"
      else
        "Other university events"
      end
    end
  end
end
