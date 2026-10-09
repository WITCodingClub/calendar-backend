# frozen_string_literal: true

# The Google service account OAuth setup. Only an owner can use it.
class ServiceAccountPolicy < ApplicationPolicy
  def manage? = owner?
end
