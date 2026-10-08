# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin user enrollments", type: :request do
  let(:admin) { create(:user, :super_admin) }
  let(:user)  { create(:user) }

  before do
    stub_request(:get, "https://api.github.com/repos/WITCodingClub/calendar/releases/latest")
      .to_return(status: 200, body: { tag_name: "v0.0.0" }.to_json)
    sign_in admin
  end

  describe "GET /admin/users/:id" do
    it "shows the instructor name when the directory gave no display name" do
      faculty = create(:faculty, first_name: "Zelda", last_name: "Quill", display_name: nil)
      course = create(:course)
      course.faculties << faculty
      create(:enrollment, user: user, course: course)

      get admin_user_path(user)

      expect(response.body).to include("Zelda Quill")
    end
  end
end
