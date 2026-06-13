# frozen_string_literal: true

# == Schema Information
#
# Table name: twenty_five_live_organizations
#
#  id                     :bigint           not null, primary key
#  code                   :string
#  name                   :string           not null
#  organization_type_name :string
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  twenty_five_live_id    :integer          not null
#
# Indexes
#
#  index_twenty_five_live_organizations_on_twenty_five_live_id  (twenty_five_live_id) UNIQUE
#
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
