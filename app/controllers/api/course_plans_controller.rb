# frozen_string_literal: true

module Api
  class CoursePlansController < ApiController
    before_action :set_course_plan, only: [:show, :update, :destroy]

    # GET /api/users/me/course_plans
    def index
      authorize CoursePlan

      plans = policy_scope(CoursePlan)
      plans = plans.by_term(Term.find_by!(uid: params[:term_uid])) if params[:term_uid].present?

      render json: plans.includes(:term, :course).map { |plan| serialize_plan(plan) }
    end

    # GET /api/users/me/course_plans/:id
    def show
      authorize @plan

      render json: serialize_plan(@plan)
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
      render json: serialize_plan(@plan), status: :created
    end

    # PATCH /api/users/me/course_plans/:id
    def update
      authorize @plan

      @plan.update!(plan_update_params)
      render json: serialize_plan(@plan)
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
          courses.map { |c| serialize_suggestion(c) }
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

    def serialize_plan(plan)
      {
        id: plan.id,
        term: TermSerializer.new(plan.term).as_json,
        subject: plan.planned_subject,
        course_number: plan.planned_course_number,
        crn: plan.planned_crn,
        course_identifier: plan.course_identifier,
        status: plan.status,
        notes: plan.notes,
        course_id: plan.course_id,
        created_at: plan.created_at,
        updated_at: plan.updated_at
      }
    end

    def serialize_suggestion(course)
      {
        id: course.id,
        subject: course.subject,
        course_number: course.course_number,
        crn: course.crn,
        title: course.title,
        credit_hours: course.credit_hours,
        schedule_type: course.schedule_type
      }
    end

  end
end
