# frozen_string_literal: true

module Oauth
  # A registration request that RFC 7591 section 3.2.2 says to refuse. The
  # code is the RFC error code, such as invalid_redirect_uri.
  class InvalidClientMetadataError < StandardError
    attr_reader :code

    def initialize(code, message)
      @code = code
      super(message)
    end
  end
end
