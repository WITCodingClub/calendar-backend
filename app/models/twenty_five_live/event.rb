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
module TwentyFiveLive
  class Event < ApplicationRecord
    self.table_name = "twenty_five_live_events"

    has_many :reservations,        class_name: "TwentyFiveLive::Reservation", foreign_key: :twenty_five_live_event_id, inverse_of: :event, dependent: :destroy
    has_many :event_organizations, class_name: "TwentyFiveLive::EventOrganization", foreign_key: :twenty_five_live_event_id, inverse_of: :event, dependent: :destroy
    has_many :organizations,       class_name: "TwentyFiveLive::Organization",      through: :event_organizations
    has_many :event_categories,    class_name: "TwentyFiveLive::EventCategory",     foreign_key: :twenty_five_live_event_id, inverse_of: :event, dependent: :destroy
    has_many :categories,          class_name: "TwentyFiveLive::Category",          through: :event_categories

    validates :event_id,      presence: true, uniqueness: true
    validates :event_locator, presence: true, uniqueness: true
    validates :event_name,    presence: true

    scope :confirmed,             -> { where(state: 2) }
    scope :public_only,           -> { where(public_website: true) }
    scope :by_cabinet,            ->(id) { where(cabinet_id: id) }
    scope :by_category_name,      ->(name) { joins(:categories).where(twenty_five_live_categories: { category_name: name }) }

  end
end
