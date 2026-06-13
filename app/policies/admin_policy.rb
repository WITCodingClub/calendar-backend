# frozen_string_literal: true

class AdminPolicy < ApplicationPolicy
  def access_admin_endpoints?
    admin?
  end
end
