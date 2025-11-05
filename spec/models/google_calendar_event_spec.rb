# == Schema Information
#
# Table name: google_calendar_events
# Database name: primary
#
#  id                 :bigint           not null, primary key
#  end_time           :datetime
#  event_data_hash    :string
#  last_synced_at     :datetime
#  location           :string
#  recurrence         :text
#  start_time         :datetime
#  summary            :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  google_calendar_id :bigint           not null
#  google_event_id    :string           not null
#  meeting_time_id    :bigint
#  user_id            :bigint           not null
#
# Indexes
#
#  index_google_calendar_events_on_google_calendar_id               (google_calendar_id)
#  index_google_calendar_events_on_google_calendar_id_and_meeting_  (google_calendar_id,meeting_time_id)
#  index_google_calendar_events_on_google_event_id                  (google_event_id)
#  index_google_calendar_events_on_meeting_time_id                  (meeting_time_id)
#  index_google_calendar_events_on_user_id                          (user_id)
#  index_google_calendar_events_on_user_id_and_meeting_time_id      (user_id,meeting_time_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (meeting_time_id => meeting_times.id)
#  fk_rails_...  (user_id => users.id)
#
require 'rails_helper'

RSpec.describe GoogleCalendarEvent, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
