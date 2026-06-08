# frozen_string_literal: true

class Building < ApplicationRecord
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :bld

  has_many :rooms, dependent: :restrict_with_exception

  def to_param
    public_id
  end
end
