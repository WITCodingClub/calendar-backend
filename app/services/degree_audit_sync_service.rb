# frozen_string_literal: true

# app/services/degree_audit_sync_service.rb
# Orchestrates degree audit parsing and storage with duplicate prevention
class DegreeAuditSyncService < ApplicationService
  require "timeout"
  require "digest"

  class ParseTimeout < StandardError; end
  class ConcurrentSyncError < StandardError; end

  SYNC_TIMEOUT = 10.seconds

  attr_reader :user, :html, :degree_program_id, :term_id

  def initialize(user:, html:, degree_program_id:, term_id:)
    @user = user
    @html = html
    @degree_program_id = degree_program_id
    @term_id = term_id
    super()
  end

  def call
    sync
  end

  def call!
    sync
  end

  # Class method convenience wrapper
  def self.sync(user:, html:, degree_program_id:, term_id:)
    new(user: user, html: html, degree_program_id: degree_program_id, term_id: term_id).call
  end

  private

  # Perform the degree audit sync with timeout and advisory lock
  def sync
    Timeout.timeout(SYNC_TIMEOUT) do
      result = ActiveRecord::Base.with_advisory_lock("degree_audit_sync_#{user.id}", timeout_seconds: 0) do
        perform_sync
      end
      raise ConcurrentSyncError, "A degree audit sync is already in progress" if result.nil?

      result
    end
  rescue Timeout::Error
    Rails.logger.warn("Degree audit sync timeout for user #{user.id}")
    raise ParseTimeout, "Sync took too long. Please try again."
  end

  # Perform the actual sync logic
  def perform_sync
    # Parse the HTML
    parser = DegreeAuditParserService.new(html: html)
    parsed_data = parser.parse

    # Check for duplicate using hash-based detection
    content_hash = calculate_content_hash(parsed_data)

    existing_snapshot = DegreeEvaluationSnapshot.find_by(
      user: user,
      degree_program_id: degree_program_id,
      content_hash: content_hash
    )

    if existing_snapshot
      Rails.logger.info("Duplicate degree audit detected for user #{user.id}, program #{degree_program_id}")
      return {
        snapshot: existing_snapshot,
        duplicate: true,
        message: "Degree audit updated (no changes detected)"
      }
    end

    # Create new snapshot
    snapshot = create_snapshot(parsed_data, content_hash)

    {
      snapshot: snapshot,
      duplicate: false,
      message: "Degree audit synced successfully"
    }
  end

  # Calculate hash for duplicate detection
  def calculate_content_hash(parsed_data)
    Digest::SHA256.hexdigest([
      user.id,
      degree_program_id,
      term_id,
      parsed_data.to_json
    ].join("-"))
  end

  # Create a new degree evaluation snapshot
  def create_snapshot(parsed_data, content_hash)
    DegreeEvaluationSnapshot.create!(
      user: user,
      degree_program_id: degree_program_id,
      evaluation_term_id: term_id,
      evaluated_at: Time.current,
      parsed_data: parsed_data,
      raw_html: html,
      content_hash: content_hash,
      total_credits_required: parsed_data.dig(:summary, :total_credits_required),
      total_credits_completed: parsed_data.dig(:summary, :total_credits_completed),
      overall_gpa: parsed_data.dig(:summary, :overall_gpa),
      evaluation_met: parsed_data.dig(:summary, :requirements_met) || false
    )
  end

end
