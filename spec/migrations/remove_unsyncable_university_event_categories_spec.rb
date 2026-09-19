# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260919230000_remove_unsyncable_university_event_categories")

# The rows are set by hand, because the app no longer saves these categories.
RSpec.describe RemoveUnsyncableUniversityEventCategories do
  subject(:migration) { described_class.new }

  let(:connection) { ActiveRecord::Base.connection }
  let(:picked_campus) { create(:user) }
  let(:picked_academic) { create(:user) }

  before do
    migration.verbose = false
    allow(GoogleCalendarSyncJob).to receive(:perform_later)
    set_categories(picked_campus, %w[deadline campus_event finals announcement])
    set_categories(picked_academic, %w[deadline finals])
  end

  def set_categories(user, categories)
    connection.execute(<<~SQL.squish)
      UPDATE user_extension_configs
      SET university_event_categories = #{connection.quote(categories.to_json)}::jsonb
      WHERE user_id = #{user.id}
    SQL
  end

  def categories_of(user) = user.user_extension_config.reload.university_event_categories

  it "removes the categories that no longer sync and keeps the order of the rest" do
    migration.migrate(:up)

    expect(categories_of(picked_campus)).to eq(%w[deadline finals])
  end

  it "leaves a selection without a removed category unchanged" do
    migration.migrate(:up)

    expect(categories_of(picked_academic)).to eq(%w[deadline finals])
  end

  it "stores an empty list when only removed categories were picked" do
    set_categories(picked_campus, %w[campus_event meeting])

    migration.migrate(:up)

    expect(categories_of(picked_campus)).to eq([])
  end

  it "marks only the people who picked a removed category for a sync" do
    migration.migrate(:up)

    expect(picked_campus.reload.calendar_needs_sync).to be(true)
    expect(picked_academic.reload.calendar_needs_sync).to be(false)
  end
end
