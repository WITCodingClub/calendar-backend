# frozen_string_literal: true

module Admin
  class CourseCatalogController < Admin::ApplicationController
    # Admin access already enforced by Admin::ApplicationController's before_action :require_admin

    def index
      authorize :course_catalog

      # Fetch available terms from LeopardWeb API
      api_result = LeopardWebService.get_available_terms
      @api_terms = api_result[:success] ? api_result[:terms] : []

      # Get existing terms from database
      @db_terms = Term.order(year: :desc, season: :desc).index_by(&:uid)

      # Build combined list showing both API and DB terms
      @combined_terms = build_combined_terms_list
    end

    def import
      authorize :course_catalog, :process?

      term_uid = params[:term_uid]
      term = Term.find_by(uid: term_uid)

      if term.nil?
        flash[:alert] = "Term not found: #{term_uid}"
        redirect_to admin_course_catalog_path
        return
      end

      # Enqueue background job to fetch and import courses
      CatalogImportJob.perform_later(term.uid)

      flash[:notice] = "Started importing courses for #{term.name} in the background. This may take a few minutes."
      redirect_to admin_course_catalog_path
    end

    def provision
      authorize :course_catalog, :process?

      term_uid = params[:term_uid].to_i
      term_description = params[:description]

      # Check if term already exists
      if Term.exists?(uid: term_uid)
        flash[:alert] = "Term #{term_uid} already exists"
        redirect_to admin_course_catalog_path
        return
      end

      # Parse term uid to get year and season
      parsed = parse_term_uid(term_uid)
      unless parsed
        flash[:alert] = "Invalid term UID format: #{term_uid}"
        redirect_to admin_course_catalog_path
        return
      end

      term = Term.create!(
        uid: term_uid,
        year: parsed[:year],
        season: parsed[:season]
      )

      flash[:notice] = "Created term: #{term.name}"
      redirect_to admin_course_catalog_path
    end

    private

    def build_combined_terms_list
      combined = []

      # Add API terms
      @api_terms.each do |api_term|
        uid = api_term[:code].to_i
        db_term = @db_terms[uid]

        combined << {
          uid: uid,
          description: api_term[:description],
          in_database: db_term.present?,
          db_term: db_term,
          from_api: true
        }
      end

      # Add any DB terms not in API (older terms)
      @db_terms.each do |uid, db_term|
        next if combined.any? { |t| t[:uid] == uid }

        combined << {
          uid: uid,
          description: db_term.name,
          in_database: true,
          db_term: db_term,
          from_api: false
        }
      end

      # Sort by uid descending (most recent first)
      combined.sort_by { |t| -t[:uid] }
    end

    def parse_term_uid(uid)
      uid_str = uid.to_s
      return nil unless uid_str.length == 6

      uid_year = uid_str[0..3].to_i
      season_code = uid_str[4..5].to_i

      # Season codes: 10 = Fall, 20 = Spring, 30 = Summer
      # Fall terms use the NEXT calendar year in the UID (e.g., Fall 2025 = 202610)
      case season_code
      when 10 # Fall
        { year: uid_year - 1, season: :fall }
      when 20 # Spring
        { year: uid_year, season: :spring }
      when 30 # Summer
        { year: uid_year, season: :summer }
      else
        nil
      end
    end
  end
end
