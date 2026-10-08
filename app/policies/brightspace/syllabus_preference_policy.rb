# frozen_string_literal: true

module Brightspace
  class SyllabusPreferencePolicy < ApplicationPolicy
    def update? = owner_of_record?
  end
end
