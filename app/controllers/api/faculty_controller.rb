# frozen_string_literal: true

module Api
  class FacultyController < ApiController
    def get_info_by_rmp_id
      rmp_id = params[:rmp_id]

      if rmp_id.blank?
        render json: { error: "rmp_id parameter is required" }, status: :bad_request
        return
      end

      faculty = Faculty.find_by(rmp_id: rmp_id)

      if faculty.nil?
        render json: { error: "Faculty not found" }, status: :not_found
        return
      end

      stats = faculty.rmp_stats

      render json: {
        faculty_name:              faculty.full_name,
        email:                     faculty.email,
        rmp_id:                    faculty.rmp_id,
        avg_rating:                stats&.dig(:avg_rating),
        avg_difficulty:            stats&.dig(:avg_difficulty),
        num_ratings:               stats&.dig(:num_ratings),
        would_take_again_percent:  stats&.dig(:would_take_again_percent),
        rmp_ratings:               faculty.rmp_all_ratings_raw
      }, status: :ok
    rescue => e
      Rails.logger.error("Error fetching RMP data for rmp_id #{rmp_id}: #{e.message}")
      render json: { error: "Failed to fetch RMP data" }, status: :internal_server_error
    end
  end
end
