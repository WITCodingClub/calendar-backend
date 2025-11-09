# frozen_string_literal: true

class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index?
    false
  end

  def show?
    false
  end

  def create?
    false
  end

  def new?
    create?
  end

  def update?
    false
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  private

  # Helper methods for access level checks

  # Any admin level access (admin, super_admin, owner)
  def admin?
    user&.admin_access?
  end

  # Super admin or owner
  def super_admin?
    user&.super_admin? || user&.owner?
  end

  # Owner only
  def owner?
    user&.owner?
  end

  # Check if user owns the record directly
  def owner_of_record?
    return false unless user && record.respond_to?(:user_id)

    record.user_id == user.id
  end

  # Check if user owns the record through an association
  def owner_of_record_through?(association)
    return false unless user && record.respond_to?(association)

    associated = record.send(association)
    return false unless associated.respond_to?(:user_id)

    associated.user_id == user.id
  end

  # Check if user can perform destructive actions on this record
  # Super admins CANNOT delete owners or owner-owned resources
  def can_perform_destructive_action?
    return false unless user

    # Determine the target user
    target_user = if record.is_a?(User)
                    record
                  elsif record.respond_to?(:user)
                    record.user
                  elsif record.respond_to?(:oauth_credential) && record.oauth_credential.respond_to?(:user)
                    record.oauth_credential.user
                  else
                    nil
                  end

    # If no target user, use super_admin? check
    return super_admin? unless target_user

    # If target is an owner, only an owner can perform destructive action
    if target_user.owner?
      owner?
    else
      super_admin?
    end
  end

  class Scope
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      raise NoMethodError, "You must define #resolve in #{self.class}"
    end

    private

    attr_reader :user, :scope

  end

end
