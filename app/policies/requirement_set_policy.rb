# frozen_string_literal: true

# The admin review of requirement sets read from a catalog PDF (#865). The
# public catalog API and the MCP tools read sets without a policy.
class RequirementSetPolicy < ApplicationPolicy
  def index?  = admin?
  def show?   = admin?
  def review? = admin?
end
