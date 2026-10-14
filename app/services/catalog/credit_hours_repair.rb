# frozen_string_literal: true

module Catalog
  # Sets each section's credit hours in one term to the import rule
  # (Catalog::Importer.credit_hours_for, from Banner's search data). Before
  # this fix, Catalog::CourseDataSyncJob copied getClassDetails "Credit Hours"
  # onto every section, so a lab got the lecture's 4 credits.
  #
  #   Catalog::CreditHoursRepair.call(term) # => { checked:, changed: }
  #
  # Catalog::CreditHoursRepairJob runs it, one term at a time.
  class CreditHoursRepair
    def self.call(term)
      new(term).call
    end

    def initialize(term)
      @term = term
    end

    def call
      result = LeopardWebClient.get_course_catalog(term: @term.uid)
      raise LeopardWebClient::RequestError, "Catalog fetch failed for #{@term.uid}: #{result[:error]}" unless result[:success]

      credits = result[:courses].to_h do |data|
        [ (data["courseReferenceNumber"] || data["crn"]).to_i, Importer.credit_hours_for(data) ]
      end

      changed = 0
      @term.courses.where(crn: credits.keys).find_each do |course|
        hours = credits[course.crn]
        next if course.credit_hours == hours

        course.update_columns(credit_hours: hours) # rubocop:disable Rails/SkipsModelValidations
        changed += 1
      end

      { checked: credits.size, changed: changed }
    end
  end
end
