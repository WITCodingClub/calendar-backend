# frozen_string_literal: true

module Courses
  # The course payload from the client is not valid, for example a course has
  # no CRN or the payload has too many sections. Controllers answer it with a
  # 400. It is an ArgumentError, so callers that rescue ArgumentError still
  # catch it.
  class InvalidPayloadError < ArgumentError; end
end
