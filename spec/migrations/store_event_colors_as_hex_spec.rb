# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260919210000_store_event_colors_as_hex")

# The test database already has the hex columns from db/schema.rb. Each example
# migrates down to the integer columns first, inside the test transaction, and
# builds the rows by hand, because the models expect the hex columns.
RSpec.describe StoreEventColorsAsHex do
  subject(:migration) { described_class.new }

  let(:connection) { ActiveRecord::Base.connection }
  let(:user) { create(:user) }

  before do
    migration.verbose = false
    migration.migrate(:down)
  end

  after do
    [ CalendarPreference, EventPreference, UserExtensionConfig ].each(&:reset_column_information)
  end

  def insert_calendar_preference(color_id)
    connection.select_value(<<~SQL.squish)
      INSERT INTO calendar_preferences (user_id, scope, event_type, color_id, created_at, updated_at)
      VALUES (#{user.id}, 1, #{connection.quote("type-#{color_id}")}, #{color_id || 'NULL'}, now(), now())
      RETURNING id
    SQL
  end

  def insert_event_preference(color_id)
    connection.select_value(<<~SQL.squish)
      INSERT INTO event_preferences (user_id, preferenceable_type, preferenceable_id, color_id, created_at, updated_at)
      VALUES (#{user.id}, 'Course::MeetingTime', 1, #{color_id}, now(), now())
      RETURNING id
    SQL
  end

  def color_of(table, id)
    connection.select_value("SELECT color_id FROM #{table} WHERE id = #{id}")
  end

  it "turns each legacy color id into the hex of its palette color" do
    ids = described_class::COLOR_IDS.keys.index_with { |color_id| insert_calendar_preference(color_id) }

    migration.migrate(:up)

    ids.each do |color_id, id|
      expect(color_of(:calendar_preferences, id)).to eq(GoogleColors::COLOR_IDS.fetch(color_id))
    end
  end

  it "migrates event preferences as well" do
    id = insert_event_preference(11)

    migration.migrate(:up)

    expect(color_of(:event_preferences, id)).to eq(GoogleColors::TOMATO)
  end

  it "keeps a preference without a color empty" do
    id = insert_calendar_preference(nil)

    migration.migrate(:up)

    expect(color_of(:calendar_preferences, id)).to be_nil
  end

  it "stores the default colors of the extension settings in lowercase, and resets a value that is not a color" do
    connection.execute(<<~SQL.squish)
      UPDATE user_extension_configs SET default_color_lecture = '#1A2B3C', default_color_lab = 'banana'
      WHERE user_id = #{user.id}
    SQL

    migration.migrate(:up)

    colors = connection.select_one("SELECT default_color_lecture, default_color_lab FROM user_extension_configs WHERE user_id = #{user.id}")
    expect(colors).to eq("default_color_lecture" => "#1a2b3c", "default_color_lab" => "#f6bf26")
  end

  it "turns palette colors back into legacy color ids on the way down" do
    migration.migrate(:up)
    palette_id = connection.select_value(<<~SQL.squish)
      INSERT INTO calendar_preferences (user_id, scope, color_id, created_at, updated_at)
      VALUES (#{user.id}, 0, '#0b8043', now(), now()) RETURNING id
    SQL
    custom_id = connection.select_value(<<~SQL.squish)
      INSERT INTO calendar_preferences (user_id, scope, color_id, created_at, updated_at)
      VALUES (#{user.id}, 3, '#1a2b3c', now(), now()) RETURNING id
    SQL

    migration.migrate(:down)

    expect(color_of(:calendar_preferences, palette_id)).to eq(10)
    expect(color_of(:calendar_preferences, custom_id)).to be_nil
  end
end
