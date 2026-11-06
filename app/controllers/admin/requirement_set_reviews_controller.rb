# frozen_string_literal: true

module Admin
  # The requirement sets that the PDF import wrote (#865). An admin compares
  # each set with its PDF and marks it as checked. A set that the import
  # writes again needs a review again.
  class RequirementSetReviewsController < Admin::ApplicationController
    PER_PAGE = 50

    before_action :set_requirement_set, only: [ :show, :update ]

    def index
      authorize RequirementSet, policy_class: RequirementSetReviewPolicy

      @reviewed = params[:status] == "reviewed"
      sets = RequirementSet.source_pdf.includes(:catalog_year, :degree_program)
      sets = @reviewed ? sets.where(needs_review: false).order(reviewed_at: :desc) : sets.where(needs_review: true)
      @requirement_sets = sets.joins(:catalog_year).order("catalog_years.start_year", :name).page(params[:page]).per(PER_PAGE)
      @waiting = RequirementSet.source_pdf.where(needs_review: true).count
    end

    def show
      authorize @requirement_set, policy_class: RequirementSetReviewPolicy

      @plans = @requirement_set.program_plans.includes(items: :catalog_course)
    end

    def update
      authorize @requirement_set, policy_class: RequirementSetReviewPolicy

      # An import may write the set again while the page is open. The check
      # is for the rows the admin saw.
      if params[:digest] != @requirement_set.source_digest
        redirect_to admin_requirement_set_review_path(@requirement_set),
                    alert: "The import changed this set after you opened it. Check the rows again."
        return
      end

      @requirement_set.update!(needs_review: false, reviewed_at: Time.current)
      redirect_to admin_requirement_set_reviews_path, notice: "Marked #{@requirement_set.name} " \
                                                              "(#{@requirement_set.catalog_year.name}) as checked."
    end

    private

    def set_requirement_set
      @requirement_set = RequirementSet.source_pdf.find(params[:id])
    end
  end
end
