# frozen_string_literal: true

module Api
  # Brightspace assignments across all classes of the signed-in user.
  class BrightspaceAssignmentsController < ApiController
    include BrightspaceFeature
    include BrightspaceScoping

    # GET /api/assignments?term_id=&status=&due_before=&page=&per_page=
    def index
      authorize Brightspace::Assignment, :index?

      scope = filter_by_term(brightspace_assignments.joins(:course_offering), "brightspace_course_offerings.term_id")
      assignments = Brightspace::AssignmentQuery.new(scope, status: params[:status], due_before: params[:due_before])
                                                .call.page(params[:page]).per(per_page)

      render json: {
        assignments: assignments.map { |assignment| Brightspace::AssignmentSerializer.new(assignment).as_json },
        meta:        pagination_meta(assignments)
      }
    end

    # GET /api/assignments/:id
    def show
      assignment = find_brightspace_assignment!(params[:id])

      render json: { assignment: Brightspace::AssignmentSerializer.new(assignment, detail: true).as_json }
    end
  end
end
