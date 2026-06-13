# frozen_string_literal: true

# == Schema Information
#
# Table name: twenty_five_live_resources
#
#  id                  :bigint           not null, primary key
#  assign_perm         :string
#  name                :string           not null
#  schedule_perm       :string
#  stock_level         :integer
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  twenty_five_live_id :integer          not null
#
# Indexes
#
#  index_twenty_five_live_resources_on_twenty_five_live_id  (twenty_five_live_id) UNIQUE
#
module TwentyFiveLive
  class Resource < ApplicationRecord
    self.table_name = "twenty_five_live_resources"

    include EncodedIds::HashidIdentifiable

    set_public_id_prefix :rsc

    validates :twenty_five_live_id, presence: true, uniqueness: true
    validates :name, presence: true

    def requestable?
      assign_perm == "R"
    end

    def schedulable?
      schedule_perm == "T"
    end

    def unlimited_stock?
      stock_level.nil?
    end

    def to_param
      public_id
    end
  end
end
