# frozen_string_literal: true

class DashboardPolicy < ApplicationPolicy
  def show?
    admin?
  end

  def index?
    admin?
  end

end
