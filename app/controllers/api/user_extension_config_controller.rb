module Api
  class UserExtensionConfigController < ApiController
    def set
      config = UserExtensionConfig.find_or_initialize_by(user_id: current_user.id)

      config.military_time = params[:military_time] unless params[:military_time].nil?
      config.default_color_lecture = params[:default_color_lecture] unless params[:default_color_lecture].nil?
      config.default_color_lab = params[:default_color_lab] unless params[:default_color_lab].nil?

      if config.save
        render json: { message: "User extension config updated successfully" }, status: :ok
      else
        render json: { error: "Failed to update user extension config", details: config.errors.full_messages }, status: :unprocessable_entity
      end
    rescue => e
      Rails.logger.error("Error updating user extension config for user #{current_user.id}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render json: { error: "Failed to update user extension config" }, status: :internal_server_error

    end

    def get
      config = current_user.user_extension_config

      if config.nil?
        render json: { error: "User extension config not found" }, status: :not_found
        return
      end

      render json: {
        military_time: config.military_time,
        default_color_lecture: config.default_color_lecture,
        default_color_lab: config.default_color_lab
      }, status: :ok
    rescue => e
      Rails.logger.error("Error fetching user extension config for user #{current_user.id}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render json: { error: "Failed to fetch user extension config" }, status: :internal_server_error
    end

  end
end
