# frozen_string_literal: true

module Api
  class CoursePlansController < ApiController
    before_action :set_course_plan, only: [:show, :update, :destroy]

    # GET /api/users/me/course_plans
    def index
      authorize CoursePlan

      plans = policy_scope(CoursePlan)
      plans = plans.by_term(Term.find_by!(uid: params[:term_uid])) if params[:term_uid].present?

      render json: plans.includes(:term, :course).map { |plan| CoursePlanSerializer.new(plan).as_json }
    end

    # GET /api/users/me/course_plans/:id
    def show
      authorize @plan

      render json: CoursePlanSerializer.new(@plan).as_json
    end

    # POST /api/users/me/course_plans
    def create
      term = Term.find_by!(uid: params[:term_uid])

      @plan = current_user.course_plans.build(
        term: term,
        planned_subject: params[:subject]&.upcase,
        planned_course_number: params[:course_number],
        planned_crn: params[:crn],
        notes: params[:notes],
        status: params[:status] || :planned
      )

      # Link to existing Course record if CRN provided
      if params[:crn].present?
        @plan.course = Course.find_by(term: term, crn: params[:crn])
      end

      authorize @plan

      @plan.save!
      render json: CoursePlanSerializer.new(@plan).as_json, status: :created
    end

    # PATCH /api/users/me/course_plans/:id
    def update
      authorize @plan

      @plan.update!(plan_update_params)
      render json: CoursePlanSerializer.new(@plan).as_json
    end

    # DELETE /api/users/me/course_plans/:id
    def destroy
      authorize @plan

      @plan.destroy!
      head :no_content
    end

    # POST /api/users/me/course_plans/generate
    def generate
      authorize CoursePlan

      terms = Array(params[:term_uids]).map { |uid| Term.find_by!(uid: uid) }
      if terms.empty?
        render json: { error: "term_uids are required" }, status: :bad_request
        return
      end

      suggestions = CoursePlannerService.new(current_user).generate_plan(terms: terms)

      render json: {
        suggestions: suggestions.transform_keys { |term| term.uid.to_s }.transform_values do |courses|
          courses.map { |c| CourseSuggestionSerializer.new(c).as_json }
        end
      }
    end

    # POST /api/users/me/course_plans/validate
    def validate
      authorize CoursePlan

      if params[:term_uid].blank?
        render json: { error: "term_uid is required" }, status: :bad_request
        return
      end

      term = Term.find_by!(uid: params[:term_uid])
      result = CoursePlannerService.new(current_user).validate_plan(term: term)

      render json: result
    end

    private

    def set_course_plan
      @plan = policy_scope(CoursePlan).find(params[:id])
    end

    def plan_update_params
      params.permit(:status, :notes, :planned_crn)
    end

  end
end
