# frozen_string_literal: true

# == Schema Information
#
# Table name: lockbox_audits
# Database name: primary
#
#  id           :bigint           not null, primary key
#  context      :string
#  data         :jsonb
#  ip           :string
#  subject_type :string
#  viewer_type  :string
#  created_at   :datetime
#  subject_id   :bigint
#  viewer_id    :bigint
#
# Indexes
#
#  index_lockbox_audits_on_subject  (subject_type,subject_id)
#  index_lockbox_audits_on_viewer   (viewer_type,viewer_id)
#
FactoryBot.define do
  factory :lockbox_audit do
    subject factory: %i[user]
    viewer factory: %i[user]

    ip { "127.0.0.1" }
    data { {} }
  end
end
