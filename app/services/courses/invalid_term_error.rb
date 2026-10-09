# frozen_string_literal: true

module Courses
  class Courses::InvalidTermError < StandardError
    attr_reader :uid

    def initialize(uid, message = nil)
      @uid = uid
      super(message || "Invalid term UID: #{uid}. Term does not exist.")
    end
  end
end
