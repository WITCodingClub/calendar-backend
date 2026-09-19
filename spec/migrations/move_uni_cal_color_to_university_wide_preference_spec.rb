# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260906180000_move_uni_cal_color_to_university_wide_preference")

RSpec.describe MoveUniCalColorToUniversityWidePreference do
  subject(:migration) { described_class.new }

  # The colors the old extension wrote: every category except study_day.
  EXTENSION_CATEGORIES = UniversityCalendarEvent::CATEGORIES - [ "study_day" ]

  def build_user(email)
    User.create!(email: email, password: "correct horse battery staple", confirmed_at: Time.current)
  end

  def set_extension_colors(user, color_id)
    EXTENSION_CATEGORIES.each do |category|
      user.calendar_preferences.create!(scope: :uni_cal_category, event_type: category, color_id: color_id)
    end
  end

  def university_color(user)
    user.calendar_preferences.find_by(scope: :uni_cal_global)&.color_id
  end

  def category_colors(user)
    user.calendar_preferences.where(scope: :uni_cal_category).pluck(:event_type, :color_id).to_h
  end

  before { migration.verbose = false }

  it "moves one shared category color to the university wide preference" do
    user = build_user("affected@wit.edu")
    set_extension_colors(user, GoogleColors::LAVENDER)

    migration.up

    expect(university_color(user)).to eq(GoogleColors::LAVENDER)
    expect(category_colors(user)).to be_empty
    expect(user.reload.calendar_needs_sync).to be(true)
  end

  it "makes study_day resolve to the chosen color" do
    user = build_user("study-day@wit.edu")
    set_extension_colors(user, GoogleColors::LAVENDER)
    event = UniversityCalendarEvent.create!(
      ics_uid: "study-day-498", summary: "Study Day", category: "study_day", all_day: true,
      start_time: Time.zone.parse("2026-08-05"), end_time: Time.zone.parse("2026-08-05 23:59")
    )

    expect(PreferenceResolver.new(user.reload).resolve_for(event)[:color_id]).to eq(GoogleColors::GRAPHITE)

    migration.up

    expect(PreferenceResolver.new(user.reload).resolve_for(event)[:color_id]).to eq(GoogleColors::LAVENDER)
  end

  it "keeps a category row that carries more than a color, minus the color" do
    user = build_user("templated@wit.edu")
    set_extension_colors(user, GoogleColors::FLAMINGO)
    user.calendar_preferences.find_by(event_type: "holiday").update!(title_template: "{{summary}}!")

    migration.up

    expect(university_color(user)).to eq(GoogleColors::FLAMINGO)
    expect(category_colors(user)).to eq({ "holiday" => nil })
    expect(user.calendar_preferences.find_by(event_type: "holiday").title_template).to eq("{{summary}}!")
  end

  it "keeps a category row that turns the reminders off" do
    user = build_user("no-reminders@wit.edu")
    set_extension_colors(user, GoogleColors::FLAMINGO)
    user.calendar_preferences.find_by(event_type: "holiday").update!(reminder_settings: [])

    migration.up

    expect(university_color(user)).to eq(GoogleColors::FLAMINGO)
    expect(category_colors(user)).to eq({ "holiday" => nil })
    expect(user.calendar_preferences.find_by(event_type: "holiday").reminder_settings).to eq([])
  end

  it "leaves a user who chose a different color per category alone" do
    user = build_user("per-category@wit.edu")
    user.calendar_preferences.create!(scope: :uni_cal_category, event_type: "holiday", color_id: GoogleColors::SAGE)
    user.calendar_preferences.create!(scope: :uni_cal_category, event_type: "finals", color_id: GoogleColors::TOMATO)

    migration.up

    expect(university_color(user)).to be_nil
    expect(category_colors(user)).to eq({ "holiday" => GoogleColors::SAGE, "finals" => GoogleColors::TOMATO })
    expect(user.reload.calendar_needs_sync).to be(false)
  end

  it "leaves a user who already has a university wide preference alone" do
    user = build_user("already-set@wit.edu")
    user.calendar_preferences.create!(scope: :uni_cal_global, color_id: GoogleColors::PEACOCK)
    set_extension_colors(user, GoogleColors::LAVENDER)

    migration.up

    expect(university_color(user)).to eq(GoogleColors::PEACOCK)
    expect(category_colors(user).values.uniq).to eq([ GoogleColors::LAVENDER ])
  end

  it "leaves a user with no university calendar color alone" do
    user = build_user("no-color@wit.edu")
    user.calendar_preferences.create!(scope: :uni_cal_category, event_type: "holiday", reminder_settings: [])
    user.calendar_preferences.create!(scope: :global, color_id: GoogleColors::FLAMINGO)

    migration.up

    expect(university_color(user)).to be_nil
    expect(user.reload.calendar_needs_sync).to be(false)
  end

  it "moves each user to their own color" do
    first  = build_user("first@wit.edu")
    second = build_user("second@wit.edu")
    set_extension_colors(first, GoogleColors::SAGE)
    set_extension_colors(second, GoogleColors::PEACOCK)

    migration.up

    expect(university_color(first)).to eq(GoogleColors::SAGE)
    expect(university_color(second)).to eq(GoogleColors::PEACOCK)
  end

  it "is safe to run twice" do
    user = build_user("rerun@wit.edu")
    set_extension_colors(user, GoogleColors::TANGERINE)

    migration.up
    expect { migration.up }.not_to raise_error

    expect(user.calendar_preferences.where(scope: :uni_cal_global).count).to eq(1)
  end
end
