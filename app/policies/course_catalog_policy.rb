# frozen_string_literal: true

class CourseCatalogPolicy < ApplicationPolicy
  def index?   = admin?
  def process? = admin?
end
