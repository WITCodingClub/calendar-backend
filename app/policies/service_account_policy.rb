# frozen_string_literal: true

# The Google service account OAuth setup (AdminAccess :service_account).
class ServiceAccountPolicy < ApplicationPolicy
  def manage? = AdminAccess.allowed?(user, :service_account)
end
