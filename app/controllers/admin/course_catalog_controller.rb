# frozen_string_literal: true

module Admin
  class CourseCatalogController < Admin::ApplicationController
    def index
      authorize :course_catalog

      api_result = LeopardWebService.get_active_terms
      @api_terms = api_result[:success] ? api_result[:terms] : []
      @db_terms  = Term.order(year: :desc, season: :desc).index_by(&:uid)

      @combined_terms = build_combined_terms_list
    end

    def import
      authorize :course_catalog, :process?

      term_uid = params[:term_uid]
      term     = Term.find_by(uid: term_uid)

      if term.nil?
        flash[:alert] = "Term not found: #{term_uid}"
        redirect_to admin_course_catalog_path
        return
      end

      job = CatalogImportJob.perform_later(term.uid)
      term.update!(catalog_importing: true, catalog_import_failed: false, catalog_import_job_id: job.job_id)
      flash[:notice] = "Started importing courses for #{term.name} in the background."
      redirect_to admin_course_catalog_path
    end

    def provision
      authorize :course_catalog, :process?

      term_uid        = params[:term_uid].to_i
      term_description = params[:description]

      if Term.exists?(uid: term_uid)
        flash[:alert] = "Term #{term_uid} already exists"
        redirect_to admin_course_catalog_path
        return
      end

      parsed = parse_term_uid(term_uid)
      unless parsed
        flash[:alert] = "Invalid term UID format: #{term_uid}"
        redirect_to admin_course_catalog_path
        return
      end

      term = Term.create!(uid: term_uid, year: parsed[:year], season: parsed[:season])
      flash[:notice] = "Created term: #{term.name}"
      redirect_to admin_course_catalog_path
    end

    private

    MIN_TERM_YEAR = 2012

    def build_combined_terms_list
      combined = @api_terms.filter_map do |api_term|
        uid    = api_term[:code].to_i
        parsed = parse_term_uid(uid)
        next unless parsed && parsed[:year] >= MIN_TERM_YEAR

        db_term = @db_terms[uid]
        { uid: uid, description: api_term[:description], in_database: db_term.present?, db_term: db_term, from_api: true }
      end

      @db_terms.each do |uid, db_term|
        next if combined.any? { |t| t[:uid] == uid }

        combined << { uid: uid, description: db_term.name, in_database: true, db_term: db_term, from_api: false }
      end

      combined.sort_by { |t| -t[:uid] }
    end

    def parse_term_uid(uid)
      uid_str = uid.to_s
      return nil unless uid_str.length == 6

      uid_year    = uid_str[0..3].to_i
      season_code = uid_str[4..5].to_i

      case season_code
      when 10 then { year: uid_year - 1, season: :fall }
      when 20 then { year: uid_year,     season: :spring }
      when 30 then { year: uid_year,     season: :summer }
      else nil
      end
    end
  end
end
