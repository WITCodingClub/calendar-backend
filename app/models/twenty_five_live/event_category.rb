# frozen_string_literal: true

# == Schema Information
#
# Table name: twenty_five_live_event_categories
# Database name: primary
#
#  id                           :bigint           not null, primary key
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  twenty_five_live_category_id :bigint           not null
#  twenty_five_live_event_id    :bigint           not null
#
# Indexes
#
#  idx_on_twenty_five_live_category_id_c676dbdbc3  (twenty_five_live_category_id)
#  idx_on_twenty_five_live_event_id_fbaea0ece2     (twenty_five_live_event_id)
#  index_tfl_event_cats_on_event_and_cat           (twenty_five_live_event_id,twenty_five_live_category_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (twenty_five_live_category_id => twenty_five_live_categories.id)
#  fk_rails_...  (twenty_five_live_event_id => twenty_five_live_events.id)
#
module TwentyFiveLive
  class EventCategory < ApplicationRecord
    self.table_name = "twenty_five_live_event_categories"

    belongs_to :event,    class_name: "TwentyFiveLive::Event",    foreign_key: :twenty_five_live_event_id,    inverse_of: :event_categories
    belongs_to :category, class_name: "TwentyFiveLive::Category", foreign_key: :twenty_five_live_category_id, inverse_of: :event_categories

  end
end
