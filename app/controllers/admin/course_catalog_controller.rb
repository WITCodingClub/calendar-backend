# frozen_string_literal: true

module Admin
  class CourseCatalogController < Admin::ApplicationController
    def index
      authorize :course_catalog

      @api_terms = banner_terms
      @db_terms  = Term.reverse_chronological.index_by(&:uid)

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

      Catalog::ImportJob.enqueue(term)
      flash[:notice] = "Started importing courses for #{term.name} in the background."
      redirect_to admin_course_catalog_path
    end

    def provision
      authorize :course_catalog, :process?

      term_uid = params[:term_uid].to_i

      if Term.exists?(uid: term_uid)
        flash[:alert] = "Term #{term_uid} already exists"
        redirect_to admin_course_catalog_path
        return
      end

      parsed = TermCode.year_and_season(term_uid)
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

    # The page still lists the stored terms when Banner does not answer.
    def banner_terms
      Catalog::LeopardWebClient.get_active_terms
    rescue Catalog::LeopardWebClient::RequestError
      []
    end

    # Banner lists terms from long before the first catalog year that the
    # app reads.
    def build_combined_terms_list
      combined = @api_terms.filter_map do |api_term|
        uid = api_term[:code].to_i
        next unless uid.to_s.match?(TermCode::CODE) && TermCode.catalog_start_year(uid) >= CatalogYear::FIRST_START_YEAR

        db_term = @db_terms[uid]
        { uid: uid, description: api_term[:description], in_database: db_term.present?, db_term: db_term, from_api: true }
      end

      @db_terms.each do |uid, db_term|
        next if combined.any? { |t| t[:uid] == uid }

        combined << { uid: uid, description: db_term.name, in_database: true, db_term: db_term, from_api: false }
      end

      combined.sort_by { |t| -t[:uid] }
    end
  end
end
