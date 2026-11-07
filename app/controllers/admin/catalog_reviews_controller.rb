# frozen_string_literal: true

module Admin
  # The review queue for degree requirements read from catalog PDFs and for
  # course code aliases (#865). A person compares each plan with its page of
  # the PDF and marks it checked. docs/degree-requirements.md.
  class CatalogReviewsController < Admin::ApplicationController
    def index
      authorize RequirementSet

      @sets = RequirementSet.where(needs_review: true).includes(:degree_program, :catalog_year)
                            .joins(:catalog_year).order("catalog_years.start_year", :name)
      @aliases = CourseCodeAlias.where(reviewed_at: nil).order(:from_subject_code, :from_course_number)
      # The whole queue is on one page: a person works down each list.
      @counts = { sets: @sets.size, aliases: @aliases.size,
                  reviewed_sets: RequirementSet.source_pdf.where.not(reviewed_at: nil).count,
                  reviewed_aliases: CourseCodeAlias.reviewed.count }
    end

    def show
      @set = RequirementSet.includes(:degree_program, :catalog_year, program_plans: :items).find(params[:id])
      authorize @set
    end

    def review
      @set = RequirementSet.find(params[:id])
      authorize @set

      @set.update!(needs_review: false, reviewed_at: Time.current)
      redirect_to admin_catalog_reviews_path, notice: "Marked #{@set.name} (#{@set.catalog_year.name}) as checked."
    end
  end
end
