# frozen_string_literal: true

# Shared serialization helpers for preference-related serializers and controllers.
# Handles reminder method aliasing ("popup" -> "notification") and color normalization.
module PreferenceSerializable
  private

  # Transform reminder settings to use "notification" instead of "popup"
  # Google Calendar uses "popup", but we alias it to "notification" in our API
  def transform_reminder_settings(reminder_settings)
    return nil if reminder_settings.nil?
    return [] if reminder_settings.empty?

    reminder_settings.map do |reminder|
      reminder = reminder.deep_symbolize_keys if reminder.is_a?(Hash)
      next reminder unless reminder.is_a?(Hash)

      reminder[:method] = "notification" if reminder[:method] == "popup"
      reminder.transform_keys(&:to_s)
    end
  end

  # Normalize color to WITCC hex format for API responses
  # Handles: integers (1-11), WITCC hex (already correct), Google event hex (convert to WITCC)
  # @param color_id_or_hex [Integer, String, nil] Color ID or hex string
  # @return [String, nil] WITCC hex color or nil
  def normalize_color_to_witcc_hex(color_id_or_hex)
    return nil if color_id_or_hex.blank?

    if color_id_or_hex.is_a?(Integer)
      return GoogleColors.to_witcc_hex(color_id_or_hex)
    end

    if color_id_or_hex.is_a?(String) && color_id_or_hex.start_with?("#")
      normalized_hex = color_id_or_hex.downcase
      return normalized_hex if GoogleColors::WITCC_MAP.key?(normalized_hex)

      return GoogleColors.to_witcc_hex(color_id_or_hex)
    end

    nil
  end
end
