# frozen_string_literal: true

# A row with an expires_at time. A nil expires_at never expires. An expired row
# counts as gone at once (scope unexpired, expired?), and
# Cleanup::ExpiredRecordsJob deletes it later with purge_expired.
module Expirable
  extend ActiveSupport::Concern

  included do
    scope :unexpired, -> { where("#{table_name}.expires_at IS NULL OR #{table_name}.expires_at > ?", Time.current) }
    scope :expired,   -> { where(expires_at: ..Time.current) }
  end

  class_methods do
    # Deletes the expired rows of the current scope and returns the count.
    # delete_all skips callbacks, so a model that must act when a row ends
    # does it in before_purge, the one path every delete of expired rows takes.
    def purge_expired
      rows = expired
      before_purge(rows)
      rows.delete_all
    end

    def before_purge(_rows); end
  end

  def expired? = expires_at.present? && expires_at <= Time.current

  private

  # A time in the past would end the row at once.
  def expires_at_in_future
    errors.add(:expires_at, "must be in the future") if expired?
  end
end
