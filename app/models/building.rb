# frozen_string_literal: true

# == Schema Information
#
# Table name: buildings
#
#  id                  :bigint           not null, primary key
#  abbreviation        :string           not null
#  formal_name         :string
#  name                :string           not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  twenty_five_live_id :integer
#
# Indexes
#
#  index_buildings_on_abbreviation         (abbreviation) UNIQUE
#  index_buildings_on_name                 (name) UNIQUE
#  index_buildings_on_twenty_five_live_id  (twenty_five_live_id) UNIQUE
#
class Building < ApplicationRecord
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :bld

  has_many :rooms, dependent: :restrict_with_exception

  def to_param
    public_id
  end
end
