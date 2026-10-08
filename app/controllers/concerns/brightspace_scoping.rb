# frozen_string_literal: true

# The Brightspace data that the read routes show: the classes of the user's
# current connection (the active one, or the last one when none is active).
# A record outside it answers 404.
module BrightspaceScoping
  extend ActiveSupport::Concern

  MAX_PER_PAGE = 100

  private

  def brightspace_connection
    return @brightspace_connection if defined?(@brightspace_connection)

    @brightspace_connection = Brightspace::Connection.current_for(current_user)
  end

  def brightspace_classes
    scope = brightspace_connection ? brightspace_connection.course_offerings : Brightspace::CourseOffering.none
    policy_scope(scope)
  end

  def brightspace_assignments
    policy_scope(Brightspace::Assignment).where(course_offering_id: brightspace_classes.select(:id))
  end

  def find_brightspace_class!(id)
    offering = brightspace_classes.find_by_public_id(id.to_s)
    raise ActiveRecord::RecordNotFound, "Class not found" unless offering

    authorize offering, :show?
    offering
  end

  def find_brightspace_assignment!(id)
    assignment = brightspace_assignments.includes(:preference, course_offering: :connection).find_by_public_id(id.to_s)
    raise ActiveRecord::RecordNotFound, "Assignment not found" unless assignment

    authorize assignment, :show?
    assignment
  end

  def per_page
    value = params[:per_page].presence&.to_i || 25
    value.clamp(1, MAX_PER_PAGE)
  end

  def pagination_meta(collection)
    {
      current_page: collection.current_page,
      total_pages:  collection.total_pages,
      total_count:  collection.total_count,
      per_page:     collection.limit_value
    }
  end

  # The term filter takes a backend term public id (trm_...), not a term uid.
  def filter_by_term(scope, column)
    return scope if params[:term_id].blank?

    term = Term.find_by_public_id(params[:term_id].to_s)
    term ? scope.where(column => term.id) : scope.none
  end
end
