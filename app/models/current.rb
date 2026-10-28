# frozen_string_literal: true

# Values memoized for one request or one job. Rails resets them when the
# request or the job ends.
class Current < ActiveSupport::CurrentAttributes
  # Term.current for each date, so a request that asks more than one time
  # sends the queries only one time.
  attribute :terms, default: -> { {} }
  # The cross-list groups of each term id, for Course#cross_listed_crns.
  attribute :cross_lists, default: -> { {} }
end
