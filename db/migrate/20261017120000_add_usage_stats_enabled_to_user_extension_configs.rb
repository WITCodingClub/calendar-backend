# frozen_string_literal: true

# The student's answer to the extension's "Share anonymous usage counts?"
# question. NULL means the student has not answered yet. The extension kept
# the answer only in browser storage, so it asked again after storage cleared.
class AddUsageStatsEnabledToUserExtensionConfigs < ActiveRecord::Migration[8.1]
  def change
    add_column :user_extension_configs, :usage_stats_enabled, :boolean
  end
end
