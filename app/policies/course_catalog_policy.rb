# frozen_string_literal: true

class CourseCatalogPolicy < ApplicationPolicy
  def index?   = AdminAccess.allowed?(user, :course_catalog)
  def process? = index?
end
