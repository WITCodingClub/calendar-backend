# frozen_string_literal: true

module Api
  # Saved hypothetical grade scenarios of one class.
  class BrightspaceGradeScenariosController < ApiController
    include BrightspaceFeature
    include BrightspaceScoping

    before_action :set_class
    before_action :set_scenario, only: [ :update, :destroy ]

    # GET /api/classes/:class_id/grade_scenarios
    def index
      scenarios = @offering.grade_scenarios.order(:created_at, :id)

      render json: { scenarios: scenarios.map { |scenario| Brightspace::GradeScenarioSerializer.new(scenario).as_json } }
    end

    # POST /api/classes/:class_id/grade_scenarios
    def create
      scenario = @offering.grade_scenarios.build(user: current_user, scores: [])
      authorize scenario

      scenario.assign_attributes(scenario_params)
      scenario.save!

      render_scenario(scenario, status: :created)
    end

    # PUT/PATCH /api/classes/:class_id/grade_scenarios/:id
    def update
      authorize @scenario
      @scenario.update!(scenario_params)

      render_scenario(@scenario)
    end

    # DELETE /api/classes/:class_id/grade_scenarios/:id
    def destroy
      authorize @scenario
      @scenario.destroy!

      head :no_content
    end

    private

    def set_class
      @offering = find_brightspace_class!(params[:class_id])
    end

    def set_scenario
      @scenario = @offering.grade_scenarios.find_by_public_id(params[:id].to_s)
      raise ActiveRecord::RecordNotFound, "Scenario not found" unless @scenario
    end

    # scores and category_overrides have a fixed shape, which GradeScenario
    # validates, so they pass as plain JSON.
    def scenario_params
      root = params.require(:grade_scenario)
      raw  = root.to_unsafe_h

      attributes = root.permit(:name).to_h
      attributes[:scores] = JSON.parse(raw["scores"].to_json) if raw.key?("scores")
      attributes[:category_overrides] = JSON.parse(raw["category_overrides"].to_json) if raw.key?("category_overrides")
      attributes
    end

    def render_scenario(scenario, status: :ok)
      render json: {
        scenario: Brightspace::GradeScenarioSerializer.new(scenario).as_json,
        version:  @offering.reload.version
      }, status: status
    end
  end
end
