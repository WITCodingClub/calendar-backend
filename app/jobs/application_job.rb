class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available.
  # Without this, a job for a deleted user fails and stays in the failed list.
  discard_on ActiveJob::DeserializationError
end
