# frozen_string_literal: true

module TwentyFiveLive
  class Organization < ApplicationRecord
    self.table_name = "twenty_five_live_organizations"

    include EncodedIds::HashidIdentifiable

    set_public_id_prefix :org

    validates :twenty_five_live_id, presence: true, uniqueness: true
    validates :name, presence: true

    def student_group?
      organization_type_name == "Student Groups"
    end

    def to_param
      public_id
    end
  end
end
