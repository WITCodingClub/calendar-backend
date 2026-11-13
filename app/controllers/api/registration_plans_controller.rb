# frozen_string_literal: true

module Api
  # The registration plans a student saves in the schedule builder of the
  # extension, one per term (#995). A plan is a help for planning, not a
  # registration. RegistrationPlan has the limits of a plan.
  class RegistrationPlansController < BaseController
    authenticate_with_token
    include Api::DegreePlanningFlag

    before_action :set_term, except: :index

    # GET /api/user/registration_plans
    # The student's plans, newest term first, without the schedule check.
    def index
      authorize RegistrationPlan, :index?
      plans = current_user.registration_plans.includes(:term).newest_first

      render json: { plans: plans.map { |plan| RegistrationPlanSerializer.new(plan).summary } }
    end

    # GET /api/user/registration_plans/:term_uid
    def show
      plan = current_user.registration_plans.find_by(term_uid: @term.uid)
      return render_error("Registration plan not found", status: :not_found) if plan.nil?

      authorize plan, :show?
      render_plan(plan)
    end

    # PUT /api/user/registration_plans/:term_uid
    # Body: courses (required) and preferences (optional). Creates the plan
    # or replaces it. A plan with conflicts still saves: the check says what
    # is wrong.
    def update
      plan = save_plan
      return render_error(plan.errors.full_messages.to_sentence, status: :unprocessable_content) if plan.errors.any?

      render_plan(plan)
    end

    # DELETE /api/user/registration_plans/:term_uid
    def destroy
      plan = current_user.registration_plans.find_by(term_uid: @term.uid)
      return render_error("Registration plan not found", status: :not_found) if plan.nil?

      authorize plan, :destroy?
      plan.destroy!

      head :no_content
    end

    private

    def set_term
      @term = Term.find_by(uid: params[:term_uid])
      render_error("Term not found", status: :not_found) if @term.nil?
    end

    # Two PUTs for the same term at the same time can both find no plan. The
    # second one then sees the first plan in the uniqueness validation, or
    # hits the unique index. It then locks the plan that the first one saved,
    # and replaces it.
    def save_plan
      plan = assign_and_save(current_user.registration_plans.find_or_initialize_by(term_uid: @term.uid))
      return plan unless plan.new_record? && plan.errors.of_kind?(:term_uid, :taken)

      replace_saved_plan
    rescue ActiveRecord::RecordNotUnique
      replace_saved_plan
    end

    def replace_saved_plan
      RegistrationPlan.transaction do
        assign_and_save(current_user.registration_plans.lock.find_by!(term_uid: @term.uid))
      end
    end

    def assign_and_save(plan)
      plan.term = @term
      plan.assign_attributes(courses: body["courses"], preferences: body["preferences"])
      authorize plan, plan.new_record? ? :create? : :update?
      plan.save
      plan
    end

    # The JSON body as plain hashes. The model keeps only the keys it knows.
    def body
      request.request_parameters
    end

    def render_plan(plan)
      plan.term = @term
      render json: RegistrationPlanSerializer.new(plan).as_json(schedule_check: plan.schedule_check)
    end
  end
end
