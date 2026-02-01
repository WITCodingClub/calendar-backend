# frozen_string_literal: true

module Admin
  class PublicIdLookupController < Admin::ApplicationController
    # Maps public_id prefixes to model classes and their path helper method names
    MODEL_MAPPING = {
      "bld" => { model: Building, path_method: :admin_building_path },
      "rom" => { model: Room, path_method: :admin_room_path },
      "trm" => { model: Term, path_method: :admin_term_path },
      "crs" => { model: Course, path_method: :admin_course_path },
      "fac" => { model: Faculty, path_method: :admin_faculty_path },
      "usr" => { model: User, path_method: :admin_user_path }
    }.freeze

    def lookup
      public_id = params[:public_id]&.strip&.downcase

      if public_id.blank?
        return render json: { error: "Public ID is required" }, status: :bad_request
      end

      prefix = public_id.split("_").first
      mapping = MODEL_MAPPING[prefix]

      unless mapping
        return render json: { error: "Unknown public ID prefix: #{prefix}" }, status: :not_found
      end

      record = mapping[:model].find_by_public_id(public_id)

      unless record
        return render json: { error: "Record not found" }, status: :not_found
      end

      # Get display name based on model type
      display_name = case record
                     when Building, Term, Faculty
                       record.name
                     when Room
                       "#{record.building&.abbreviation} #{record.number}"
                     when Course
                       "#{record.code} - #{record.title}"
                     when User
                       record.emails.where(primary: true).first&.email || record.emails.first&.email || "User ##{record.id}"
                     else
                       record.to_s
                     end

      render json: {
        public_id: record.public_id,
        type: mapping[:model].name,
        display_name: display_name,
        path: send(mapping[:path_method], record)
      }
    rescue => e
      Rails.logger.error("PublicIdLookup error: #{e.class}: #{e.message}")
      Rails.logger.error(e.backtrace.first(10).join("\n"))
      render json: { error: "Internal error: #{e.message}" }, status: :internal_server_error
    end

    def redirect
      public_id = params[:public_id]&.strip&.downcase

      if public_id.blank?
        flash[:alert] = "Public ID is required"
        return redirect_to admin_root_path
      end

      prefix = public_id.split("_").first
      mapping = MODEL_MAPPING[prefix]

      unless mapping
        flash[:alert] = "Unknown public ID prefix: #{prefix}"
        return redirect_to admin_root_path
      end

      record = mapping[:model].find_by_public_id(public_id)

      unless record
        flash[:alert] = "Record not found for public ID: #{public_id}"
        return redirect_to admin_root_path
      end

      redirect_to send(mapping[:path_method], record)
    end

  end
end
