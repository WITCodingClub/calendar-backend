# frozen_string_literal: true

module Brightspace
  class AssignmentPreferencePolicy < ApplicationPolicy
    def show?   = owner_of_record?
    def update? = owner_of_record?
  end
end
