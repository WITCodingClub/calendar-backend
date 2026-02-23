# frozen_string_literal: true

module Api
  class CrnListController < ApiController
    # GET /api/users/me/crn_list?term_uid=202430
    def index
      authorize current_user, :show?

      term_uid = params[:term_uid]
      if term_uid.blank?
        render json: { error: "term_uid is required" }, status: :bad_request
        return
      end

      term = Term.find_by(uid: term_uid)
      if term.nil?
        render json: { error: "Term not found" }, status: :not_found
        return
      end

      result = CrnListGeneratorService.call(user: current_user, term: term)
      render json: result, status: :ok
    end

    # POST /api/users/me/crn_list/courses
    # Add a course to the user's plan for a term
    def add_course
      authorize current_user, :update?

      term = Term.find_by(uid: params[:term_uid])
      return render json: { error: "Term not found" }, status: :not_found if term.nil?

      plan = current_user.course_plans.build(
        term: term,
        planned_subject: params[:subject]&.upcase,
        planned_course_number: params[:course_number],
        planned_crn: params[:crn],
        notes: params[:notes],
        status: :planned
      )

      # Try to link to an existing Course record
      if params[:crn].present?
        plan.course = Course.find_by(
          term: term,
          crn: params[:crn]
        )
      end

      if plan.save
        render json: {
          plan_id: plan.id,
          message: "Course added to plan"
        }, status: :created
      else
        render json: { error: plan.errors.full_messages.join(", ") }, status: :unprocessable_content
      end
    end

    # DELETE /api/users/me/crn_list/courses/:id
    def remove_course
      plan = current_user.course_plans.find_by(id: params[:id])
      return render json: { error: "Course plan not found" }, status: :not_found if plan.nil?

      authorize plan, :destroy?
      plan.destroy!
      render json: { ok: true }, status: :ok
    end

  end
end
