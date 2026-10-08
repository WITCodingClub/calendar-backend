# frozen_string_literal: true

# == Schema Information
#
# Table name: brightspace_connections
#
#  id                    :bigint           not null, primary key
#  connected_at          :datetime         not null
#  disconnected_at       :datetime
#  host                  :string           not null
#  last_synced_at        :datetime
#  reconnect_required_at :datetime
#  status                :string           default("active"), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  learner_id            :string           not null
#  user_id               :bigint           not null
#
# Indexes
#
#  index_brightspace_connections_on_identity          (user_id,host,learner_id) UNIQUE
#  index_brightspace_connections_on_user_id           (user_id)
#  index_brightspace_connections_one_active_per_user  (user_id) UNIQUE WHERE ((status)::text = 'active'::text)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :brightspace_connection, class: "Brightspace::Connection" do
    association :user
    host { "brightspace.example.edu" }
    sequence(:learner_id) { |n| (90_000 + n).to_s }
    status { "active" }
    connected_at { Time.current }

    trait :disconnected do
      status { "disconnected" }
      disconnected_at { Time.current }
    end
  end
end
