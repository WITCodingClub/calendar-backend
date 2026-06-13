# frozen_string_literal: true

class RiscController < ApplicationController
  skip_before_action :verify_authenticity_token

  def create
    token = extract_token_from_request

    if token.blank?
      render json: { error: "Security event token missing" }, status: :bad_request
      return
    end

    ProcessRiscEventJob.perform_later(token)
    head :accepted
  rescue => e
    Rails.logger.error("Error receiving RISC event: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    head :bad_request
  end

  private

  def extract_token_from_request
    request.body.rewind
    body = request.body.read

    begin
      parsed = JSON.parse(body)
      parsed["token"] || parsed["jwt"] || body
    rescue JSON::ParserError
      body
    end
  end
end
