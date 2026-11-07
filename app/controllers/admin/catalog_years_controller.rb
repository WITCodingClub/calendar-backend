# frozen_string_literal: true

module Admin
  # The degree requirements import (#864): the catalog years with their
  # source and status, a button that queues the import of one year, the
  # programs of a year, and the report that compares the year's courses with
  # Banner. The :id of a route is the start year (2024 for 2024-2025).
  class CatalogYearsController < Admin::ApplicationController
    # The first catalog year that the catalog site has as HTML. Older years
    # are PDFs (#865). The same year as lib/tasks/degree_requirements.rake.
    FIRST_HTML_YEAR = 2019

    def index
      authorize CatalogYear

      stored = CatalogYear.all.index_by(&:start_year)
      start_years = (stored.keys | (FIRST_HTML_YEAR..Date.current.year).to_a).sort.reverse
      @catalog_years = start_years.map { |start_year| stored[start_year] || CatalogYear.new(start_year: start_year) }
      @queued = DegreeRequirements::ImportJob.queued_start_years
      @program_counts = RequirementSet.group(:catalog_year_id).count
      @course_counts = CatalogYearCourse.group(:catalog_year_id).count
    end

    def show
      @catalog_year = CatalogYear.find_by!(start_year: params[:id])
      authorize @catalog_year

      sets = @catalog_year.requirement_sets.includes(:degree_program, :catalog_year).order(:name)
      sets = sets.where("requirement_sets.name ILIKE ?", "%#{RequirementSet.sanitize_sql_like(params[:search].to_s.strip)}%") if params[:search].present?
      @requirement_sets = sets.page(params[:page]).per(50)
      @plan_counts = ProgramPlan.where(requirement_set_id: @requirement_sets.map(&:id)).group(:requirement_set_id).count
      @list_counts = ElectiveGroup.where(requirement_set_id: @requirement_sets.map(&:id)).group(:requirement_set_id).count
      @queued = DegreeRequirements::ImportJob.queued_start_years.include?(@catalog_year.start_year)
    end

    def import
      authorize CatalogYear, :import?

      start_year = Integer(params[:id], exception: false)
      name = start_year && "#{start_year}-#{start_year + 1}"
      if start_year.nil? || !start_year.between?(FIRST_HTML_YEAR, Date.current.year + 1)
        redirect_to admin_catalog_years_path, alert: "The import reads catalog years from #{FIRST_HTML_YEAR} to #{Date.current.year + 1}."
      elsif CatalogYear.source_pdf.exists?(start_year: start_year)
        # The HTML import cannot read a year from a PDF (#865).
        redirect_to admin_catalog_years_path, alert: "#{name} comes from a PDF. The HTML import cannot read it."
      elsif DegreeRequirements::ImportJob.queued_start_years.include?(start_year)
        redirect_to admin_catalog_years_path, alert: "An import of #{name} is already in the queue."
      else
        force = params[:force] == "1"
        DegreeRequirements::ImportJob.perform_later(start_year, force: force)
        redirect_to admin_catalog_years_path, notice: "Queued the import of #{name}#{' with force' if force}."
      end
    end

    def course_comparison
      @catalog_year = CatalogYear.find_by!(start_year: params[:id])
      authorize @catalog_year

      @comparison = DegreeRequirements::CourseComparison.new(@catalog_year)
      @kind = DegreeRequirements::CourseComparison::KINDS.find { |kind| kind.to_s == params[:kind] } || :catalog_only
      @counts = @comparison.counts
      @rows = Kaminari.paginate_array(@comparison.rows(@kind)).page(params[:page]).per(50)
    end
  end
end
