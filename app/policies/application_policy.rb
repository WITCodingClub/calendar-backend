# frozen_string_literal: true

class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index?   = false
  def show?    = false
  def create?  = false
  def new?     = create?
  def update?  = false
  def edit?    = update?
  def destroy? = false

  private

  def admin?
    user&.admin_access?
  end

  def super_admin?
    user&.super_admin? || user&.owner?
  end

  def owner?
    user&.owner?
  end

  def owner_of_record?
    return false unless user

    if record.respond_to?(:user_id) && record.user_id.present?
      return record.user_id == user.id
    end

    if record.respond_to?(:user) && record.user.present?
      return record.user.id == user.id
    end

    false
  end

  def owner_of_record_through?(association)
    return false unless user && record.respond_to?(association)

    associated = record.send(association)
    return false unless associated.respond_to?(:user_id)

    associated.user_id == user.id
  end

  def can_perform_destructive_action?
    return false unless user

    target_user = if record.is_a?(User)
                    record
    elsif record.respond_to?(:user)
                    record.user
    elsif record.respond_to?(:oauth_credential) && record.oauth_credential.respond_to?(:user)
                    record.oauth_credential.user
    end

    return super_admin? unless target_user

    target_user.owner? ? owner? : super_admin?
  end

  class Scope
    def initialize(user, scope)
      @user  = user
      @scope = scope
    end

    def resolve
      raise NoMethodError, "You must define #resolve in #{self.class}"
    end

    private

    attr_reader :user, :scope
  end
end
