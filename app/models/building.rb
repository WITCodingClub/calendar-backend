# frozen_string_literal: true

# == Schema Information
#
# Table name: buildings
#
#  id                          :bigint           not null, primary key
#  abbreviation                :string           not null
#  formal_name                 :string
#  name                        :string           not null
#  twenty_five_live_checked_at :datetime
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  twenty_five_live_id         :integer
#
# Indexes
#
#  index_buildings_on_abbreviation         (abbreviation) UNIQUE
#  index_buildings_on_name                 (name) UNIQUE
#  index_buildings_on_twenty_five_live_id  (twenty_five_live_id) UNIQUE
#
class Building < ApplicationRecord
  include EncodedIds::HashidIdentifiable

  # LeopardWeb files a section with no room under one of these. They are not
  # real buildings, and 25Live has no building for them.
  PLACEHOLDER_ABBREVIATIONS = %w[TBD ONLINE].freeze

  # The 25Live sync runs weekly. A check older than this means a sync was missed.
  TWENTY_FIVE_LIVE_CHECK_STALE_AFTER = 8.days

  set_public_id_prefix :bld

  has_many :rooms, dependent: :restrict_with_exception

  scope :physical, -> { where.not("UPPER(abbreviation) IN (?)", PLACEHOLDER_ABBREVIATIONS) }

  def to_param
    public_id
  end

  # How this building compares with 25Live. A building with no formal name is
  # only "not in 25Live" once a recent sync has finished looking for it.
  def twenty_five_live_status(sync_in_progress: false)
    if formal_name.present?
      name == formal_name ? :match : :mismatch
    elsif sync_in_progress
      :syncing
    elsif twenty_five_live_checked_at.nil?
      :never_synced
    elsif twenty_five_live_checked_at < TWENTY_FIVE_LIVE_CHECK_STALE_AFTER.ago
      :stale
    else
      :not_in_25live
    end
  end
end
