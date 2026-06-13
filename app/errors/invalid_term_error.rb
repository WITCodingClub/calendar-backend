# frozen_string_literal: true

class InvalidTermError < StandardError
  attr_reader :uid

  def initialize(uid, message = nil)
    @uid = uid
    super(message || "Invalid term UID: #{uid}. Term does not exist.")
  end
end
