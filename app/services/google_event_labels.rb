# frozen_string_literal: true

# Google Calendar shows a custom event color through an event label. Each
# calendar holds up to 200 labels, and each label has a background color. An
# event takes the color of the label that its eventLabelId names.
#
# This class finds the label for a color on the course calendar, and adds the
# label when the calendar has none. The service must have owner access to the
# calendar. A calendar that cannot take labels makes #available? false, and the
# caller then sends the nearest legacy colorId.
class GoogleEventLabels
  include GoogleApiRateLimiter

  MAX_LABELS = 200

  def initialize(service, calendar_id)
    @service     = service
    @calendar_id = calendar_id
  end

  def available?
    labels
    @available
  end

  # Returns the id of the label for the "#rrggbb" color, or nil when the
  # calendar cannot take the label.
  def label_id_for(hex)
    return nil unless available?

    labels[hex] || add_label(hex)
  end

  private

  # Maps each label color to the label id.
  def labels
    return @labels if defined?(@labels)

    calendar   = with_rate_limit_handling { @service.get_calendar(@calendar_id) }
    @available = true
    @labels    = labels_by_color(calendar)
  rescue Google::Apis::Error => e
    unavailable!(e)
    @labels = {}
  end

  def add_label(hex)
    return nil if labels.size >= MAX_LABELS

    label_id = SecureRandom.uuid
    event_labels = current_event_labels + [ Google::Apis::CalendarV3::EventLabel.new(id: label_id, background_color: hex) ]
    calendar = Google::Apis::CalendarV3::Calendar.new(
      label_properties: Google::Apis::CalendarV3::LabelProperties.new(event_labels: event_labels)
    )

    updated = with_rate_limit_handling { @service.patch_calendar(@calendar_id, calendar) }
    @labels = labels_by_color(updated)
    return label_id if @labels[hex] == label_id

    # Google did not keep the label, so this calendar cannot take labels.
    unavailable!(nil)
    nil
  rescue Google::Apis::Error => e
    unavailable!(e)
    nil
  end

  # The labels as Google holds them. A patch replaces the full list, so send
  # every label back, including labels that a person added.
  def current_event_labels
    @event_labels || []
  end

  def labels_by_color(calendar)
    @event_labels = calendar.label_properties&.event_labels || []
    @event_labels.each_with_object({}) do |label, by_color|
      color = label.background_color&.downcase
      by_color[color] ||= label.id if color && label.id
    end
  end

  def unavailable!(error)
    @available = false
    Rails.logger.warn({ message: "Google Calendar event labels unavailable, using legacy color ids",
                        calendar_id: @calendar_id, error: error&.message }.to_json)
  end
end
