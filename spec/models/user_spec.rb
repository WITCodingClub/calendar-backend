# frozen_string_literal: true

# == Schema Information
#
# Table name: users
# Database name: primary
#
#  id                    :bigint           not null, primary key
#  access_level          :integer          default("user"), not null
#  calendar_needs_sync   :boolean          default(FALSE), not null
#  calendar_token        :string
#  first_name            :string
#  last_calendar_sync_at :datetime
#  last_name             :string
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#
# Indexes
#
#  index_users_on_calendar_needs_sync    (calendar_needs_sync)
#  index_users_on_calendar_token         (calendar_token) UNIQUE
#  index_users_on_last_calendar_sync_at  (last_calendar_sync_at)
#
require "rails_helper"

RSpec.describe User do
  pending "add some examples to (or delete) #{__FILE__}"
end
