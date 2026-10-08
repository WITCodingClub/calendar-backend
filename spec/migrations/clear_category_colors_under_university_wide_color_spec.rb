# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261007100600_clear_category_colors_under_university_wide_color")

# The preference rows are built by hand, because the CalendarPreference model
# now clears category colors itself when a university wide color is saved.
RSpec.describe ClearCategoryColorsUnderUniversityWideColor do
  subject(:migration) { described_class.new }

  let(:connection) { ActiveRecord::Base.connection }
  let(:user) { create(:user) }

  before { migration.verbose = false }

  def insert_preference(user, scope:, event_type: nil, color_id: nil, title_template: nil)
    scopes = { "uni_cal_category" => 2, "uni_cal_global" => 3 }
    connection.execute(<<~SQL.squish)
      INSERT INTO calendar_preferences (user_id, scope, event_type, color_id, title_template, created_at, updated_at)
      VALUES (#{user.id}, #{scopes.fetch(scope)}, #{connection.quote(event_type)}, #{connection.quote(color_id)},
              #{connection.quote(title_template)}, NOW(), NOW())
    SQL
  end

  def category_rows(user)
    connection.select_rows(<<~SQL.squish).to_h { |event_type, color_id, title| [ event_type, [ color_id, title ] ] }
      SELECT event_type, color_id, title_template FROM calendar_preferences
      WHERE user_id = #{user.id} AND scope = 2
    SQL
  end

  def university_color(user)
    connection.select_value("SELECT color_id FROM calendar_preferences WHERE user_id = #{user.id} AND scope = 3")
  end

  it "clears the category colors of a user with a university wide color and keeps the other fields" do
    insert_preference(user, scope: "uni_cal_global", color_id: "#1a2b3c")
    insert_preference(user, scope: "uni_cal_category", event_type: "holiday", color_id: "#d50000")
    insert_preference(user, scope: "uni_cal_category", event_type: "finals", color_id: "#0b8043",
                            title_template: "{{summary}}")

    migration.migrate(:up)

    expect(category_rows(user)).to eq("holiday" => [ nil, nil ], "finals" => [ nil, "{{summary}}" ])
    expect(university_color(user)).to eq("#1a2b3c")
  end

  it "marks only the users it changed for a sync" do
    unchanged = create(:user)
    insert_preference(user, scope: "uni_cal_global", color_id: "#1a2b3c")
    insert_preference(user, scope: "uni_cal_category", event_type: "holiday", color_id: "#d50000")
    insert_preference(unchanged, scope: "uni_cal_global", color_id: "#1a2b3c")

    migration.migrate(:up)

    expect(user.reload.calendar_needs_sync).to be(true)
    expect(unchanged.reload.calendar_needs_sync).to be(false)
  end

  it "leaves a user whose university wide row has no color alone" do
    insert_preference(user, scope: "uni_cal_global")
    insert_preference(user, scope: "uni_cal_category", event_type: "holiday", color_id: "#d50000")

    migration.migrate(:up)

    expect(category_rows(user)).to eq("holiday" => [ "#d50000", nil ])
    expect(user.reload.calendar_needs_sync).to be(false)
  end

  it "leaves a user with no university wide row alone" do
    insert_preference(user, scope: "uni_cal_category", event_type: "holiday", color_id: "#d50000")

    migration.migrate(:up)

    expect(category_rows(user)).to eq("holiday" => [ "#d50000", nil ])
  end

  it "covers users in more than one batch" do
    stub_const("#{described_class}::BATCH_SIZE", 1)
    other = create(:user)
    [ user, other ].each do |person|
      insert_preference(person, scope: "uni_cal_global", color_id: "#1a2b3c")
      insert_preference(person, scope: "uni_cal_category", event_type: "holiday", color_id: "#d50000")
    end

    migration.migrate(:up)

    expect(category_rows(user)).to eq("holiday" => [ nil, nil ])
    expect(category_rows(other)).to eq("holiday" => [ nil, nil ])
  end

  it "changes nothing on the way down" do
    insert_preference(user, scope: "uni_cal_global", color_id: "#1a2b3c")
    insert_preference(user, scope: "uni_cal_category", event_type: "holiday", color_id: "#d50000")
    migration.migrate(:up)

    expect { migration.migrate(:down) }.not_to raise_error
    expect(category_rows(user)).to eq("holiday" => [ nil, nil ])
  end
end
