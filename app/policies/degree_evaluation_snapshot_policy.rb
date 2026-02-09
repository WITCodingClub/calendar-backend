# frozen_string_literal: true

# app/policies/degree_evaluation_snapshot_policy.rb
# Authorization policy for degree audit snapshots
class DegreeEvaluationSnapshotPolicy < ApplicationPolicy
  # User-owned resource: users can only access their own degree audit snapshots

  # Users can view their own degree audit snapshots
  def show?
    user_owns_record?
  end

  # Users can list their own degree audit snapshots
  def index?
    true # Any authenticated user can list their own snapshots
  end

  # Users can create their own degree audit snapshots
  def create?
    true # Any authenticated user can create snapshots
  end

  # Users can sync/update their own degree audit snapshots
  def update?
    user_owns_record?
  end

  # Users can delete their own degree audit snapshots
  def destroy?
    user_owns_record?
  end

  # Scope: users can only see their own snapshots
  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(user: user)
    end

  end

  private

  def user_owns_record?
    record.user_id == user.id
  end

end
