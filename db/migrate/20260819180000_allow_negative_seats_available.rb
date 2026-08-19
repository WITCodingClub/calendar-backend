# frozen_string_literal: true

# Banner reports seats_available as maximumEnrollment - enrollment, so an
# over-enrolled section is a negative number. About 17% of sections in a term
# are over-enrolled. The old constraint rejected them, so ingest stored 0 and
# the section looked full rather than over capacity.
class AllowNegativeSeatsAvailable < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :courses, name: "courses_seats_available_non_negative"
  end

  def down
    add_check_constraint :courses,
                         "seats_available IS NULL OR seats_available >= 0",
                         name: "courses_seats_available_non_negative"
  end
end
