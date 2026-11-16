# frozen_string_literal: true

require "rails_helper"

# Issue #1020: AP, test, and transfer credit from the transcript or the student.
RSpec.describe "/api/user/transfer_credits", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_headers_for(user) }

  def put_credits(credits)
    put "/api/user/transfer_credits", params: { credits: credits }, headers: headers, as: :json
  end

  it "answers 404 while the degree_planning flag is off" do
    get "/api/user/transfer_credits", headers: headers

    expect(response).to have_http_status(:not_found)
  end

  context "with the degree_planning flag", :degree_planning do
    it "lists the student's credits by code, and not another student's" do
      create(:transfer_credit, user: user, code: "MATH 1750", kind: "ap")
      create(:transfer_credit, :student, user: user, code: "ENGL 1100")
      create(:transfer_credit, code: "HIST 1000")

      get "/api/user/transfer_credits", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["credits"].map { |credit| credit.slice("code", "source", "kind", "removable") }).to eq([
        { "code" => "ENGL 1100", "source" => "student", "kind" => nil, "removable" => true },
        { "code" => "MATH 1750", "source" => "transcript", "kind" => "ap", "removable" => false }
      ])
    end

    describe "PUT" do
      it "replaces the transcript entries and keeps the entries the student added" do
        create(:transfer_credit, user: user, code: "HIST 1000")
        create(:transfer_credit, :student, user: user, code: "PSYC 1000")
        create(:transfer_credit, :student, user: user, code: "ENGL 1100", title: "Student title")

        put_credits([
          { code: "ENGL 1100", title: "English I", credits: 4, kind: "ap" },
          { code: "math1750", title: "Calculus I", credits: 4.0, kind: "TEST" },
          { code: "PHYS 1250", title: "Physics I", credits: "4.000" },
          { code: "HUMN 1XXX", title: "Humanities Elective", credits: 4 },
          { code: "MATH 1750", title: "Calculus I again", credits: 4 }
        ])

        expect(response).to have_http_status(:ok)
        expect(user.transfer_credits.order(:code).pluck(:code, :source, :kind, :title, :credits)).to match([
          [ "ENGL 1100", "student", nil, "Student title", 4 ],
          [ "MATH 1750", "transcript", "test", "Calculus I", 4 ],
          [ "PHYS 1250", "transcript", nil, "Physics I", 4 ],
          [ "PSYC 1000", "student", nil, anything, 4 ]
        ])
        expect(response.parsed_body["credits"].pluck("code")).to eq([ "ENGL 1100", "MATH 1750", "PHYS 1250", "PSYC 1000" ])
        expect(response.parsed_body["skipped"]).to eq([
          { "code" => "ENGL 1100", "reason" => "student_entry" },
          { "code" => "HUMN 1XXX", "reason" => "not_a_course_code" },
          { "code" => "MATH 1750", "reason" => "duplicate" }
        ])
      end

      it "removes every transcript entry with an empty list" do
        create(:transfer_credit, user: user)
        create(:transfer_credit, :student, user: user, code: "PSYC 1000")

        put_credits([])

        expect(response).to have_http_status(:ok)
        expect(user.transfer_credits.pluck(:code)).to eq([ "PSYC 1000" ])
      end

      it "skips an entry with credits or a kind that is not valid, and stores the others" do
        put_credits([ { code: "ENGL 1100", credits: 4 }, { code: "MATH 1750", credits: 99 },
                      { code: "PHYS 1250", credits: 3.5 }, { code: "HIST 1000", kind: "clep" } ])

        expect(response).to have_http_status(:ok)
        expect(user.transfer_credits.pluck(:code)).to eq([ "ENGL 1100" ])
        expect(response.parsed_body["skipped"].map { |entry| entry.values_at("code", "reason") }).to eq([
          [ "MATH 1750", "invalid" ], [ "PHYS 1250", "invalid" ], [ "HIST 1000", "invalid" ]
        ])
        expect(response.parsed_body["skipped"].first["message"]).to include("Credits")
      end

      it "answers 422 and changes nothing for a body that is not a list of objects with a code" do
        create(:transfer_credit, user: user, code: "HIST 1000")

        put_credits([ { code: "ENGL 1100" }, { code: 1100 } ])

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body).to include("code" => "invalid_transfer_credit", "error" => "credits[1].code must be a string")
        expect(user.transfer_credits.pluck(:code)).to eq([ "HIST 1000" ])

        put "/api/user/transfer_credits", params: {}, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["error"]).to eq("credits must be a list")
      end
    end

    describe "POST" do
      it "adds a catalog course as a student entry, with the catalog title and credits" do
        create(:catalog_course, subject_code: "ENGL", course_number: 1100, title: "English I", credit_hours: 4)

        post "/api/user/transfer_credits", params: { code: "engl 1100" }, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        expect(response.parsed_body).to include("code" => "ENGL 1100", "title" => "English I", "credits" => 4,
                                                "source" => "student", "removable" => true)
        expect(user.transfer_credits.sole).to have_attributes(code: "ENGL 1100", source: "student")
      end

      it "answers 422 for a code that is not a catalog course, and for a code the student has" do
        post "/api/user/transfer_credits", params: { code: "ENGL 1100" }, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["code"]).to eq("unknown_course")

        create(:catalog_course, subject_code: "ENGL", course_number: 1100)
        create(:transfer_credit, user: user, code: "ENGL 1100")
        post "/api/user/transfer_credits", params: { code: "ENGL 1100", credits: 3 }, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["code"]).to eq("duplicate")
      end
    end

    describe "DELETE" do
      it "removes a student entry" do
        create(:transfer_credit, :student, user: user, code: "ENGL 1100")

        delete "/api/user/transfer_credits/ENGL%201100", headers: headers

        expect(response).to have_http_status(:no_content)
        expect(user.transfer_credits).to be_empty
      end

      it "refuses to remove a transcript entry, because the next sync would bring it back" do
        create(:transfer_credit, user: user, code: "ENGL 1100")

        delete "/api/user/transfer_credits/ENGL1100", headers: headers

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["code"]).to eq("transcript_entry")
        expect(user.transfer_credits.count).to eq(1)
      end

      it "answers 404 for another student's entry" do
        create(:transfer_credit, :student, code: "ENGL 1100")

        delete "/api/user/transfer_credits/ENGL%201100", headers: headers

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
