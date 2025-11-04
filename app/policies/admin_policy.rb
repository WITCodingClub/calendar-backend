# frozen_string_literal: true

class AdminPolicy < ApplicationPolicy
  def blazer?
    user&.admin? || user&.super_admin? || user&.owner?
  end

  def flipper?
    user&.super_admin? || user&.owner?
  end

  def access_admin_endpoints?
    user&.admin? || user&.super_admin? || user&.owner?
  end

end
