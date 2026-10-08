# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Brightspace class preference API", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_headers_for(user) }
  let(:offering) { create(:brightspace_course_offering, connection: create(:brightspace_connection, user: user)) }
  let(:path) { "/api/classes/#{offering.public_id}/preference" }

  def json = response.parsed_body

  before { Flipper.enable_actor(FlipperFlags::BRIGHTSPACE, user) }

  it "returns the defaults" do
    get path, headers: headers

    expect(json["class_preference"]["calendar"]).to include("sync_enabled" => true, "included_kinds" => %w[assignment quiz discussion])
    expect(json["version"]).to eq(offering.version)
  end

  it "saves calendar and grade settings" do
    category = create(:brightspace_grade_category, course_offering: offering)

    put path, params: {
      class_preference: {
        calendar: {
          sync_enabled: false, included_kinds: [ "quiz" ], title_template: "{{title}} due", color_id: "#D50000",
          reminder_settings: [ { time: "1", type: "days", method: "notification" } ]
        },
        grades: { mode: "custom", categories: [ { category_id: category.public_id, weight: 50, drop_lowest: 1 } ] }
      }
    }, headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(json["class_preference"]["calendar"]).to include(
      "sync_enabled" => false, "included_kinds" => [ "quiz" ], "title_template" => "{{title}} due", "color_id" => "#d50000",
      "reminder_settings" => [ { "time" => "1", "type" => "days", "method" => "notification" } ]
    )
    expect(json["class_preference"]["grades"]).to eq(
      "mode" => "custom", "categories" => [ { "category_id" => category.public_id, "weight" => 50, "drop_lowest" => 1 } ]
    )
    expect(json["version"]).not_to eq(offering.version)
  end

  it "changes only the fields in the body" do
    create(:brightspace_class_preference, course_offering: offering, title_template: "Keep", grade_mode: "syllabus",
                                          reminder_settings: [ { "time" => "30", "type" => "minutes", "method" => "popup" } ])

    put path, params: { class_preference: { calendar: { color_id: "#0b8043" } } }, headers: headers, as: :json

    calendar = json["class_preference"]["calendar"]
    expect(calendar).to include("title_template" => "Keep", "color_id" => "#0b8043")
    expect(calendar["reminder_settings"]).to eq([ { "time" => "30", "type" => "minutes", "method" => "notification" } ])
    expect(json["class_preference"]["grades"]["mode"]).to eq("syllabus")
  end

  it "keeps [] apart from \"default\" for reminders" do
    put path, params: { class_preference: { calendar: { reminder_settings: [] } } }, headers: headers, as: :json
    expect(json["class_preference"]["calendar"]["reminder_settings"]).to eq([])

    put path, params: { class_preference: { calendar: { reminder_settings: "default" } } }, headers: headers, as: :json
    expect(json["class_preference"]["calendar"]["reminder_settings"]).to be_nil
  end

  it "answers 422 for bad rules" do
    put path, params: { class_preference: { grades: { mode: "vibes" } } }, headers: headers, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(json["error"]).to match(/Grade mode/)
  end

  it "answers 404 for another user's class" do
    get "/api/classes/#{create(:brightspace_course_offering).public_id}/preference", headers: headers

    expect(response).to have_http_status(:not_found)
  end
end
