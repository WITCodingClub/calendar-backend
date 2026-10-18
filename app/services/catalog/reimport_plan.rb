# frozen_string_literal: true

module Catalog
  # The terms that catalog:reimport_all_terms imports again, newest first, so
  # the current and future terms finish first.
  #
  # A term is in the plan when Banner lists it and it is in our database. A
  # Banner term that is not in our database is reported, not created: create it
  # on the admin course catalog page first. A term that is only in our database
  # is reported too, because Banner has nothing to import for it.
  class ReimportPlan
    Result = Data.define(:term_uids, :missing_in_database, :missing_in_banner)

    def initialize(from: nil, to: nil)
      @from = from.presence&.to_i
      @to   = to.presence&.to_i
    end

    # @raise [Catalog::LeopardWebClient::RequestError] when Banner does not list its terms
    def call
      result = Catalog::LeopardWebClient.get_active_terms
      raise Catalog::LeopardWebClient::RequestError, "Banner did not list its terms: #{result[:error]}" unless result[:success]

      banner_uids = result[:terms].map { |term| term[:code].to_i }.select { |uid| in_bounds?(uid) }
      db_uids     = Term.pluck(:uid).select { |uid| in_bounds?(uid) }

      Result.new(
        term_uids:           (banner_uids & db_uids).sort.reverse,
        missing_in_database: (banner_uids - db_uids).sort.reverse,
        missing_in_banner:   (db_uids - banner_uids).sort.reverse
      )
    end

    private

    def in_bounds?(uid)
      (@from.nil? || uid >= @from) && (@to.nil? || uid <= @to)
    end
  end
end
