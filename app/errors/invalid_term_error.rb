# frozen_string_literal: true

# Error raised when an invalid term UID is provided
class InvalidTermError < StandardError
  attr_reader :uid

  def initialize(uid, message = nil)
    @uid = uid
    @message = message || "Invalid term UID: #{uid}. Term does not exist."
    super(@message)
  end
end
