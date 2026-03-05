# frozen_string_literal: true

# == Schema Information
#
# Table name: twenty_five_live_event_organizations
# Database name: primary
#
#  id                               :bigint           not null, primary key
#  primary                          :boolean          default(FALSE), not null
#  created_at                       :datetime         not null
#  updated_at                       :datetime         not null
#  twenty_five_live_event_id        :bigint           not null
#  twenty_five_live_organization_id :bigint           not null
#
# Indexes
#
#  idx_on_twenty_five_live_event_id_90d70194d5         (twenty_five_live_event_id)
#  idx_on_twenty_five_live_organization_id_829b355159  (twenty_five_live_organization_id)
#  index_tfl_event_orgs_on_event_and_org               (twenty_five_live_event_id,twenty_five_live_organization_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (twenty_five_live_event_id => twenty_five_live_events.id)
#  fk_rails_...  (twenty_five_live_organization_id => twenty_five_live_organizations.id)
#
module TwentyFiveLive
  class EventOrganization < ApplicationRecord
    self.table_name = "twenty_five_live_event_organizations"

    belongs_to :event,        class_name: "TwentyFiveLive::Event",        foreign_key: :twenty_five_live_event_id,        inverse_of: :event_organizations
    belongs_to :organization, class_name: "TwentyFiveLive::Organization", foreign_key: :twenty_five_live_organization_id, inverse_of: :event_organizations

  end
end
