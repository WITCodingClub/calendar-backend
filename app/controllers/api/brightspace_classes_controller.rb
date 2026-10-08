# frozen_string_literal: true

module Api
  # Brightspace classes of the signed-in user. See docs/brightspace.md.
  class BrightspaceClassesController < ApiController
    include BrightspaceFeature
    include BrightspaceScoping

    UPCOMING_LIMIT      = 10
    ANNOUNCEMENTS_LIMIT = 20

    # GET /api/classes?term_id=&page=&per_page=
    def index
      authorize Brightspace::CourseOffering, :index?

      classes = filter_by_term(brightspace_classes, :term_id)
                .includes(:course, :term).order(:title, :id)
                .page(params[:page]).per(per_page)
      deadlines = Brightspace::AssignmentQuery.next_deadlines(classes.map(&:id))

      render json: {
        classes: classes.map { |offering| class_json(offering, deadlines[offering.id]) },
        meta:    pagination_meta(classes)
      }
    end

    # GET /api/classes/:id
    def show
      offering = find_brightspace_class!(params[:id])
      upcoming = Brightspace::AssignmentQuery.new(offering.assignments).call
                                             .where("#{Brightspace::Assignment::EFFECTIVE_DUE_AT_SQL} >= ?", Time.current)
                                             .where("COALESCE(brightspace_assignment_preferences.progress, 'not_started') <> 'done'")
                                             .limit(UPCOMING_LIMIT)
      announcements = offering.announcements.not_removed
                              .order(Arel.sql("posted_at DESC NULLS LAST"), id: :desc).limit(ANNOUNCEMENTS_LIMIT)

      render json: {
        class:                class_json(offering, upcoming.first),
        upcoming_assignments: upcoming.map { |assignment| Brightspace::AssignmentSerializer.new(assignment).as_json },
        announcements:        announcements.map { |announcement| Brightspace::AnnouncementSerializer.new(announcement).as_json },
        preferences:          Brightspace::ClassPreferenceSerializer.new(offering.preference).as_json,
        sync:                 Brightspace::ClassStatusSerializer.new(offering).as_json[:sections]
      }
    end

    # GET /api/classes/:id/assignments
    def assignments
      offering    = find_brightspace_class!(params[:id])
      assignments = Brightspace::AssignmentQuery.new(offering.assignments, status: params[:status], due_before: params[:due_before])
                                                .call.page(params[:page]).per(per_page)

      render json: {
        assignments: assignments.map { |assignment| Brightspace::AssignmentSerializer.new(assignment).as_json },
        meta:        pagination_meta(assignments)
      }
    end

    private

    def class_json(offering, next_deadline)
      Brightspace::ClassSerializer.new(offering, connection: brightspace_connection, next_deadline: next_deadline).as_json
    end
  end
end
