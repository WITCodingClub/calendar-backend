# frozen_string_literal: true

# app/lib/api_error_codes.rb
# Standardized error codes for API responses
module ApiErrorCodes
  # Authentication
  AUTH_MISSING = "AUTH_MISSING"
  AUTH_EXPIRED = "AUTH_EXPIRED"
  AUTH_INVALID = "AUTH_INVALID"

  # External Session
  SESSION_EXPIRED = "SESSION_EXPIRED" # LeopardWeb session expired (not our JWT)

  # Validation
  VALIDATION_FAILED = "VALIDATION_FAILED"
  INVALID_PROGRAM = "INVALID_PROGRAM"

  # Processing
  PARSE_ERROR = "PARSE_ERROR"
  NO_AUDIT_AVAILABLE = "NO_AUDIT_AVAILABLE"
  CONCURRENT_SYNC = "CONCURRENT_SYNC"

  # Rate Limiting
  RATE_LIMITED = "RATE_LIMITED"

  # Server
  SERVER_ERROR = "SERVER_ERROR"
end
