# frozen_string_literal: true

# Controller for receiving Google RISC (Risk and Incident Sharing and Coordination)
# security event webhooks
class RiscController < ApplicationController
  # Skip authentication - this is a public webhook endpoint
  skip_before_action :verify_authenticity_token

  # Receive security event token from Google
  # POST /risc/events
  def create
    # Extract the JWT token from the request body
    token = extract_token_from_request

    if token.blank?
      render json: { error: "Security event token missing" }, status: :bad_request
      return
    end

    # Enqueue background job to process the event
    # This allows us to return 202 Accepted immediately
    ProcessRiscEventJob.perform_later(token)

    # Return HTTP 202 as required by RISC spec
    head :accepted
  rescue => e
    Rails.logger.error("Error receiving RISC event: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))

    # Return HTTP 400 for invalid requests
    head :bad_request
  end

  private

  # Extract JWT token from request body
  # Google sends the token as a raw string in the body
  def extract_token_from_request
    request.body.rewind
    body = request.body.read

    # Try to parse as JSON first (in case it's wrapped)
    begin
      parsed = JSON.parse(body)
      parsed["token"] || parsed["jwt"] || body
    rescue JSON::ParserError
      # If not JSON, treat the body as the raw token
      body
    end
  end
end
