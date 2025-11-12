# frozen_string_literal: true

module Admin
  class CourseCatalogController < Admin::ApplicationController
    # Admin access already enforced by Admin::ApplicationController's before_action :require_admin

    def index
      authorize :course_catalog
      @terms = Term.order(year: :desc, season: :desc)
      # Show the form for fetching course catalog
    end

    def fetch
      authorize :course_catalog
      @terms = Term.order(year: :desc, season: :desc)

      # Extract parameters
      term = params[:term]
      jsessionid = params[:jsessionid]
      idmsessid = params[:idmsessid]

      if term.blank? || jsessionid.blank?
        flash[:alert] = "Term and JSESSIONID are required"
        redirect_to admin_course_catalog_path
        return
      end

      # Fetch courses using the service
      result = LeopardWebService.get_course_catalog(
        term: term,
        jsessionid: jsessionid,
        idmsessid: idmsessid.presence
      )

      if result[:success]
        @courses = result[:courses]
        @total_count = result[:total_count]
        @raw_response = result[:raw_response] # For debugging

        # Check if term has already been imported
        @term_record = Term.find_by(uid: term)
        @term_already_imported = @term_record&.catalog_imported?
        @term_imported_at = @term_record&.catalog_imported_at

        if @total_count == 0
          flash.now[:alert] = "API returned 0 courses. This might mean: (1) Invalid/expired cookies, (2) No courses for this term, or (3) API authentication issue. Check the raw response below."
        else
          flash.now[:notice] = "Successfully fetched #{@total_count} courses for term #{term}"
        end
      else
        flash.now[:alert] = "Error fetching courses: #{result[:error]}"
      end

      render :index
    rescue => e
      flash[:alert] = "Unexpected error: #{e.message}"
      @terms = Term.order(year: :desc, season: :desc)
      redirect_to admin_course_catalog_path
    end

    def import_courses
      authorize :course_catalog, :process?
      courses_json = params[:courses]

      if courses_json.blank?
        flash[:alert] = "No courses data provided"
        redirect_to admin_course_catalog_path
        return
      end

      # Parse JSON string back to array
      begin
        courses = JSON.parse(courses_json)
      rescue JSON::ParserError => e
        flash[:alert] = "Invalid courses data: #{e.message}"
        redirect_to admin_course_catalog_path
        return
      end

      # Enqueue background job to process courses
      CatalogImportJob.perform_later(courses)

      flash[:notice] = "Started processing #{courses.count} courses in the background. This may take several minutes. Check the logs or database for progress."
      redirect_to admin_course_catalog_path
    rescue => e
      flash[:alert] = "Unexpected error: #{e.message}"
      redirect_to admin_course_catalog_path
    end
  end
end
