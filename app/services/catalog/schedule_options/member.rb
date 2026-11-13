# frozen_string_literal: true

module Catalog
  module ScheduleOptions
    # One section of a unit, with its meetings, and true when the student
    # pinned its CRN.
    Member = Data.define(:course, :slots, :pinned)
  end
end
