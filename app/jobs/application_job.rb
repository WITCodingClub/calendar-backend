# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  # A job for a record that was deleted after it was queued has nothing to do.
  # Without this, it fails and stays in the failed list.
  discard_on ActiveJob::DeserializationError
end
