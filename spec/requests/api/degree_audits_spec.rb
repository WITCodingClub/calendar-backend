# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API::DegreeAudits", :openapi do
  let(:user) { create(:user) }
  let(:jwt_token) { JsonWebTokenService.encode(user_id: user.id) }
  let(:auth_headers) { { "Authorization" => "Bearer #{jwt_token}" } }
  let(:degree_program) { create(:degree_program) }
  let(:term) { create(:term) }
  let(:html_content) { Rails.root.join("spec/fixtures/leopard_web/degree_audit/valid_single_program.html").read }

  describe "POST /api/users/me/degree_audit/sync" do
    let(:valid_params) do
      {
        html: html_content,
        degree_program_id: degree_program.id,
        term_id: term.id
      }
    end

    context "with valid authentication and params" do
      it "syncs degree audit and returns snapshot" do
        post "/api/users/me/degree_audit/sync", params: valid_params, headers: auth_headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["success"]).to be true
        expect(json["data"]).to include(
          "id",
          "evaluated_at",
          "gpa",
          "credits_earned",
          "credits_remaining",
          "percent_complete",
          "parsed_data"
        )
        expect(json["data"]["parsed_data"]).to include(
          "program_info",
          "requirements",
          "completed_courses",
          "in_progress_courses",
          "summary"
        )
      end

      it "returns 'updated' message for duplicate sync" do
        # First sync
        post "/api/users/me/degree_audit/sync", params: valid_params, headers: auth_headers
        expect(response).to have_http_status(:ok)
        first_json = response.parsed_body
        expect(first_json["message"]).to eq("Degree audit synced successfully")

        # Second sync with same data
        post "/api/users/me/degree_audit/sync", params: valid_params, headers: auth_headers
        expect(response).to have_http_status(:ok)
        second_json = response.parsed_body
        expect(second_json["message"]).to eq("Degree audit updated (no changes detected)")
      end
    end

    context "with missing authentication" do
      it "returns 401 unauthorized" do
        post "/api/users/me/degree_audit/sync", params: valid_params

        expect(response).to have_http_status(:unauthorized)
        json = response.parsed_body
        expect(json["success"]).to be false
        expect(json["code"]).to eq("AUTH_MISSING")
      end
    end

    context "with invalid JWT token" do
      it "returns 401 unauthorized" do
        post "/api/users/me/degree_audit/sync",
             params: valid_params,
             headers: { "Authorization" => "Bearer invalid_token" }

        expect(response).to have_http_status(:unauthorized)
        json = response.parsed_body
        expect(json["success"]).to be false
        expect(json["code"]).to eq("AUTH_INVALID")
      end
    end

    context "with missing required params" do
      it "returns 400 for missing html" do
        post "/api/users/me/degree_audit/sync",
             params: { degree_program_id: degree_program.id, term_id: term.id },
             headers: auth_headers

        expect(response).to have_http_status(:bad_request)
        json = response.parsed_body
        expect(json["success"]).to be false
        expect(json["code"]).to eq("VALIDATION_FAILED")
      end

      it "returns 400 for missing degree_program_id" do
        post "/api/users/me/degree_audit/sync",
             params: { html: html_content, term_id: term.id },
             headers: auth_headers

        expect(response).to have_http_status(:bad_request)
        json = response.parsed_body
        expect(json["success"]).to be false
        expect(json["code"]).to eq("VALIDATION_FAILED")
      end

      it "returns 400 for missing term_id" do
        post "/api/users/me/degree_audit/sync",
             params: { html: html_content, degree_program_id: degree_program.id },
             headers: auth_headers

        expect(response).to have_http_status(:bad_request)
        json = response.parsed_body
        expect(json["success"]).to be false
        expect(json["code"]).to eq("VALIDATION_FAILED")
      end
    end

    context "with invalid params" do
      it "returns 400 for empty html" do
        post "/api/users/me/degree_audit/sync",
             params: { html: "", degree_program_id: degree_program.id, term_id: term.id },
             headers: auth_headers

        expect(response).to have_http_status(:bad_request)
        json = response.parsed_body
        expect(json["success"]).to be false
        expect(json["code"]).to eq("VALIDATION_FAILED")
      end

      it "returns 400 for invalid degree_program_id" do
        post "/api/users/me/degree_audit/sync",
             params: { html: html_content, degree_program_id: -1, term_id: term.id },
             headers: auth_headers

        expect(response).to have_http_status(:bad_request)
        json = response.parsed_body
        expect(json["success"]).to be false
        expect(json["code"]).to eq("VALIDATION_FAILED")
      end

      it "returns 400 for invalid term_id" do
        post "/api/users/me/degree_audit/sync",
             params: { html: html_content, degree_program_id: degree_program.id, term_id: 0 },
             headers: auth_headers

        expect(response).to have_http_status(:bad_request)
        json = response.parsed_body
        expect(json["success"]).to be false
        expect(json["code"]).to eq("VALIDATION_FAILED")
      end
    end

    context "with malformed HTML" do
      it "returns 422 with parse error" do
        post "/api/users/me/degree_audit/sync",
             params: {
               html: "<html><body>Invalid structure</body></html>",
               degree_program_id: degree_program.id,
               term_id: term.id
             },
             headers: auth_headers

        expect(response).to have_http_status(:unprocessable_content)
        json = response.parsed_body
        expect(json["success"]).to be false
        expect(json["code"]).to eq("PARSE_ERROR")
      end
    end

    context "with concurrent sync attempt" do
      it "returns 409 conflict" do
        # Mock advisory lock failure
        allow(ActiveRecord::Base).to receive(:with_advisory_lock).and_raise(
          DegreeAuditSyncService::ConcurrentSyncError.new("A degree audit sync is already in progress")
        )

        post "/api/users/me/degree_audit/sync", params: valid_params, headers: auth_headers

        expect(response).to have_http_status(:conflict)
        json = response.parsed_body
        expect(json["success"]).to be false
        expect(json["code"]).to eq("CONCURRENT_SYNC")
      end
    end
  end

  describe "GET /api/users/me/degree_audit" do
    context "with existing snapshot" do
      let!(:snapshot) { create(:degree_evaluation_snapshot, user: user, degree_program: degree_program) }

      it "returns the most recent snapshot" do
        get "/api/users/me/degree_audit",
            params: { degree_program_id: degree_program.id },
            headers: auth_headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["success"]).to be true
        expect(json["data"]["id"]).to eq(snapshot.id)
        expect(json["data"]).to include(
          "evaluated_at",
          "gpa",
          "credits_earned",
          "credits_remaining",
          "percent_complete",
          "parsed_data"
        )
      end
    end

    context "without existing snapshot" do
      it "returns 404 not found" do
        get "/api/users/me/degree_audit",
            params: { degree_program_id: degree_program.id },
            headers: auth_headers

        expect(response).to have_http_status(:not_found)
        json = response.parsed_body
        expect(json["success"]).to be false
        expect(json["code"]).to eq("NO_AUDIT_AVAILABLE")
      end
    end

    context "with missing degree_program_id" do
      it "returns 400 bad request" do
        get "/api/users/me/degree_audit", headers: auth_headers

        expect(response).to have_http_status(:bad_request)
        json = response.parsed_body
        expect(json["success"]).to be false
        expect(json["code"]).to eq("VALIDATION_FAILED")
      end
    end

    context "with invalid degree_program_id" do
      it "returns 400 bad request" do
        get "/api/users/me/degree_audit",
            params: { degree_program_id: -1 },
            headers: auth_headers

        expect(response).to have_http_status(:bad_request)
        json = response.parsed_body
        expect(json["success"]).to be false
        expect(json["code"]).to eq("VALIDATION_FAILED")
      end
    end

    context "without authentication" do
      it "returns 401 unauthorized" do
        get "/api/users/me/degree_audit", params: { degree_program_id: degree_program.id }

        expect(response).to have_http_status(:unauthorized)
        json = response.parsed_body
        expect(json["success"]).to be false
        expect(json["code"]).to eq("AUTH_MISSING")
      end
    end

    context "when user tries to access another user's snapshot" do
      let(:other_user) { create(:user) }
      let!(:other_snapshot) { create(:degree_evaluation_snapshot, user: other_user, degree_program: degree_program) }

      it "returns 404 (policy scope filters by user)" do
        get "/api/users/me/degree_audit",
            params: { degree_program_id: degree_program.id },
            headers: auth_headers

        expect(response).to have_http_status(:not_found)
        json = response.parsed_body
        expect(json["success"]).to be false
        expect(json["code"]).to eq("NO_AUDIT_AVAILABLE")
      end
    end
  end

  describe "GET /api/users/me/degree_audit/history" do
    context "with existing snapshots" do
      let!(:snapshots) do
        [
          create(:degree_evaluation_snapshot, user: user, degree_program: degree_program, evaluated_at: 3.days.ago),
          create(:degree_evaluation_snapshot, user: user, degree_program: degree_program, evaluated_at: 2.days.ago),
          create(:degree_evaluation_snapshot, user: user, degree_program: degree_program, evaluated_at: 1.day.ago)
        ]
      end

      it "returns paginated snapshots in reverse chronological order" do
        get "/api/users/me/degree_audit/history",
            params: { degree_program_id: degree_program.id },
            headers: auth_headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["success"]).to be true
        expect(json["data"]["snapshots"].length).to eq(3)

        # Check reverse chronological order
        expect(json["data"]["snapshots"][0]["id"]).to eq(snapshots[2].id)
        expect(json["data"]["snapshots"][1]["id"]).to eq(snapshots[1].id)
        expect(json["data"]["snapshots"][2]["id"]).to eq(snapshots[0].id)

        # Check pagination metadata
        expect(json["data"]["pagination"]).to include(
          "current_page" => 1,
          "total_pages"  => 1,
          "total_count"  => 3,
          "per_page"     => 20
        )
      end

      it "supports custom pagination" do
        get "/api/users/me/degree_audit/history",
            params: { degree_program_id: degree_program.id, page: 1, per_page: 2 },
            headers: auth_headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["data"]["snapshots"].length).to eq(2)
        expect(json["data"]["pagination"]).to include(
          "current_page" => 1,
          "total_pages"  => 2,
          "total_count"  => 3,
          "per_page"     => 2
        )
      end

      it "enforces max per_page of 100" do
        get "/api/users/me/degree_audit/history",
            params: { degree_program_id: degree_program.id, per_page: 200 },
            headers: auth_headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["data"]["pagination"]["per_page"]).to eq(100)
      end

      it "filters by degree_program_id" do
        other_program = create(:degree_program, :business)
        create(:degree_evaluation_snapshot, user: user, degree_program: other_program)

        get "/api/users/me/degree_audit/history",
            params: { degree_program_id: degree_program.id },
            headers: auth_headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["data"]["snapshots"].length).to eq(3)
        expect(json["data"]["snapshots"].all? { |s| s["degree_program_id"] == degree_program.id }).to be true
      end
    end

    context "without snapshots" do
      it "returns empty array" do
        get "/api/users/me/degree_audit/history",
            params: { degree_program_id: degree_program.id },
            headers: auth_headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["success"]).to be true
        expect(json["data"]["snapshots"]).to eq([])
        expect(json["data"]["pagination"]["total_count"]).to eq(0)
      end
    end

    context "with missing degree_program_id" do
      it "returns 400 bad request" do
        get "/api/users/me/degree_audit/history", headers: auth_headers

        expect(response).to have_http_status(:bad_request)
        json = response.parsed_body
        expect(json["success"]).to be false
        expect(json["code"]).to eq("VALIDATION_FAILED")
      end
    end

    context "with invalid degree_program_id" do
      it "returns 400 bad request" do
        get "/api/users/me/degree_audit/history",
            params: { degree_program_id: 0 },
            headers: auth_headers

        expect(response).to have_http_status(:bad_request)
        json = response.parsed_body
        expect(json["success"]).to be false
        expect(json["code"]).to eq("VALIDATION_FAILED")
      end
    end

    context "without authentication" do
      it "returns 401 unauthorized" do
        get "/api/users/me/degree_audit/history", params: { degree_program_id: degree_program.id }

        expect(response).to have_http_status(:unauthorized)
        json = response.parsed_body
        expect(json["success"]).to be false
        expect(json["code"]).to eq("AUTH_MISSING")
      end
    end

    context "when user tries to access another user's history" do
      let(:other_user) { create(:user) }
      let!(:other_snapshots) do
        create_list(:degree_evaluation_snapshot, 2, user: other_user, degree_program: degree_program)
      end

      it "returns empty array (policy scope filters by user)" do
        get "/api/users/me/degree_audit/history",
            params: { degree_program_id: degree_program.id },
            headers: auth_headers

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["success"]).to be true
        expect(json["data"]["snapshots"]).to eq([])
        expect(json["data"]["pagination"]["total_count"]).to eq(0)
      end
    end
  end
end
