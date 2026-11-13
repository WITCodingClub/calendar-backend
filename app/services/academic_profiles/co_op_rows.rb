# frozen_string_literal: true

module AcademicProfiles
  # The one test for a co-op semester row of a plan of study. PlanTerms,
  # PlanEstimate, and the summary of DegreeProgress use it.
  #
  # A co-op semester is COOP 3500 or COOP 4500 (required) or COOP 5000
  # (additional). COOP 2500 is a normal course row.
  module CoOpRows
    # The codes of a co-op semester, as "COOP 3500".
    CODES = DegreeRequirements::SharedElectives::CO_OP_TERMS.map { |code| code.join(" ") }.freeze

    module_function

    # A row of the Co-op elective list, or a co-op course row (COOP 3500),
    # or a choice of co-op courses. Most plans list a co-op semester as a
    # course row with no elective list.
    def co_op?(row)
      return true if row[:elective_list] == DegreeRequirements::SharedElectives::CO_OP.name

      codes = [ row[:code], *row[:options] ].compact
      codes.any? && codes.all? { |code| CODES.include?(code) }
    end
  end
end
