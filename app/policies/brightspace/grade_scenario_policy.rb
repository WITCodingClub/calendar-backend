# frozen_string_literal: true

module Brightspace
  class GradeScenarioPolicy < ApplicationPolicy
    def show?    = owner_of_record?
    def create?  = owner_of_record?
    def update?  = owner_of_record?
    def destroy? = owner_of_record?
  end
end
