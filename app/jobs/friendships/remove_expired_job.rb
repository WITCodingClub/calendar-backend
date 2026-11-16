# frozen_string_literal: true

# Renamed to Cleanup::ExpiredRecordsJob. Jobs that were in the queue before the
# deploy still run. Remove this alias when `bin/rails jobs:unknown_class_names`
# on production lists no job with this name.
module Friendships
  RemoveExpiredJob = Cleanup::ExpiredRecordsJob
end
