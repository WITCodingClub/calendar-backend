# frozen_string_literal: true

module Admin
  class PublicIdLookupController < ApplicationController
    before_action :authenticate_user!

    # Maps public_id prefixes to model classes and their admin path helpers
    MODEL_MAPPING = {
      "bld" => { model: Building, path: ->(record) { admin_building_path(record) } },
      "rom" => { model: Room, path: ->(record) { admin_room_path(record) } },
      "trm" => { model: Term, path: ->(record) { admin_term_path(record) } },
      "crs" => { model: Course, path: ->(record) { admin_course_path(record) } },
      "fac" => { model: Faculty, path: ->(record) { admin_faculty_path(record) } },
      "usr" => { model: User, path: ->(record) { admin_user_path(record) } }
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
        path: mapping[:path].call(record)
      }
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

      redirect_to mapping[:path].call(record)
    end

  end
end
