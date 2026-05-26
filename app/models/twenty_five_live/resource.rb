# frozen_string_literal: true

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
