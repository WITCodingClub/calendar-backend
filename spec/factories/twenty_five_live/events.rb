# frozen_string_literal: true

# == Schema Information
#
# Table name: twenty_five_live_events
# Database name: primary
#
#  id               :bigint           not null, primary key
#  cabinet_name     :string
#  creation_dt      :datetime
#  description      :text
#  end_date         :date
#  event_locator    :string           not null
#  event_name       :string           not null
#  event_title      :string
#  event_type_name  :string
#  last_mod_dt      :datetime
#  last_synced_at   :datetime
#  public_website   :boolean          default(FALSE), not null
#  registration_url :string
#  start_date       :date
#  state            :integer
#  state_name       :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  cabinet_id       :integer
#  event_id         :integer          not null
#  event_type_id    :integer
#
# Indexes
#
#  index_twenty_five_live_events_on_event_id       (event_id) UNIQUE
#  index_twenty_five_live_events_on_event_locator  (event_locator) UNIQUE
#
FactoryBot.define do
  factory :"twenty_five_live/event", class: "TwentyFiveLive::Event" do
    sequence(:event_id)      { |n| 100_000 + n }
    sequence(:event_locator) { |n| "2026-EVENT#{n}" }
    sequence(:event_name)    { |n| "Event #{n}" }
    event_title              { nil }
    start_date               { Date.current }
    end_date                 { Date.current }
    event_type_id            { 10 }
    event_type_name          { "Student Event" }
    state                    { 2 }
    state_name               { "Confirmed" }
    cabinet_id               { 50 }
    cabinet_name             { "Student Activities" }
    public_website           { false }
  end
end
