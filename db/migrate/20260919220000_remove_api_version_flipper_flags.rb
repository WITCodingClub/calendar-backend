# frozen_string_literal: true

# The 2025_10_04_v1 and 2025_11_12_v2 flags gated the API during the beta. The
# gate is gone, so their rows only clutter the Flipper UI.
class RemoveApiVersionFlipperFlags < ActiveRecord::Migration[8.1]
  FLAGS = %w[2025_10_04_v1 2025_11_12_v2].freeze

  def up
    execute "DELETE FROM flipper_gates WHERE feature_key IN (#{quoted_flags})"
    execute "DELETE FROM flipper_features WHERE key IN (#{quoted_flags})"
  end

  # Nothing reads these flags, so a rollback does not bring them back.
  def down; end

  private

  def quoted_flags
    FLAGS.map { |flag| connection.quote(flag) }.join(", ")
  end
end
