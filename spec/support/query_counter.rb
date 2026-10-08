# frozen_string_literal: true

# Counts the SQL queries that a block sends to the database. Cached reads,
# schema lookups, and transaction statements are not counted, so the number
# is the work that grows with the data.
module QueryCounter
  IGNORED_NAMES = %w[SCHEMA TRANSACTION].freeze
  TRANSACTION_SQL = /\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE SAVEPOINT)\b/i

  def count_queries(&block)
    count = 0
    counter = lambda do |*, payload|
      next if payload[:cached] || IGNORED_NAMES.include?(payload[:name])
      next if payload[:sql].match?(TRANSACTION_SQL)

      count += 1
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end
end

RSpec.configure do |config|
  config.include QueryCounter
end
