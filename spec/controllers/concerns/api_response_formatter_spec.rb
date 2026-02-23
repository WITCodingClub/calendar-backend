# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApiResponseFormatter do
  controller(ActionController::Base) do
    include ApiResponseFormatter # rubocop:disable RSpec/DescribedClass

    def success_test
      success_response(data: { id: 1, name: "Test" }, message: "Operation successful")
    end

    def success_no_message
      success_response(data: { id: 2 })
    end

    def error_test
      error_response(error: "Something went wrong", code: ApiErrorCodes::VALIDATION_FAILED)
    end

    def auth_error_test
      auth_error("Token expired", code: ApiErrorCodes::AUTH_EXPIRED)
    end

    def validation_error_test
      validation_error("Invalid input")
    end

    def not_found_test
      not_found_error("Resource not found")
    end

    def success_created_test
      success_response(data: { test: true }, status: :created)
    end

    def server_error_test
      error_response(error: "Server error", code: ApiErrorCodes::SERVER_ERROR, status: :internal_server_error)
    end

    def auth_error_default_test
      auth_error
    end
  end

  before do
    routes.draw {
      get "success_test" => "anonymous#success_test"
      get "success_no_message" => "anonymous#success_no_message"
      get "error_test" => "anonymous#error_test"
      get "auth_error_test" => "anonymous#auth_error_test"
      get "validation_error_test" => "anonymous#validation_error_test"
      get "not_found_test" => "anonymous#not_found_test"
      get "success_created_test" => "anonymous#success_created_test"
      get "server_error_test" => "anonymous#server_error_test"
      get "auth_error_default_test" => "anonymous#auth_error_default_test"
    }
  end

  describe "#success_response" do
    it "returns standardized success format with message" do
      get :success_test

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["success"]).to be(true)
      expect(json["data"]).to eq({ "id" => 1, "name" => "Test" })
      expect(json["message"]).to eq("Operation successful")
    end

    it "returns success format without message" do
      get :success_no_message

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["success"]).to be(true)
      expect(json["data"]).to eq({ "id" => 2 })
      expect(json).not_to have_key("message")
    end

    it "allows custom status codes" do
      get :success_created_test

      expect(response).to have_http_status(:created)
    end
  end

  describe "#error_response" do
    it "returns standardized error format" do
      get :error_test

      expect(response).to have_http_status(:bad_request)
      json = response.parsed_body
      expect(json["success"]).to be(false)
      expect(json["error"]).to eq("Something went wrong")
      expect(json["code"]).to eq(ApiErrorCodes::VALIDATION_FAILED)
    end

    it "allows custom status codes" do
      get :server_error_test

      expect(response).to have_http_status(:internal_server_error)
    end
  end

  describe "#auth_error" do
    it "returns unauthorized status with auth error code" do
      get :auth_error_test

      expect(response).to have_http_status(:unauthorized)
      json = response.parsed_body
      expect(json["success"]).to be(false)
      expect(json["error"]).to eq("Token expired")
      expect(json["code"]).to eq(ApiErrorCodes::AUTH_EXPIRED)
    end

    it "uses default message if none provided" do
      get :auth_error_default_test

      json = response.parsed_body
      expect(json["error"]).to eq("Authentication required")
      expect(json["code"]).to eq(ApiErrorCodes::AUTH_MISSING)
    end
  end

  describe "#validation_error" do
    it "returns unprocessable entity status" do
      get :validation_error_test

      expect(response).to have_http_status(:unprocessable_content)
      json = response.parsed_body
      expect(json["success"]).to be(false)
      expect(json["error"]).to eq("Invalid input")
      expect(json["code"]).to eq(ApiErrorCodes::VALIDATION_FAILED)
    end
  end

  describe "#not_found_error" do
    it "returns not found status" do
      get :not_found_test

      expect(response).to have_http_status(:not_found)
      json = response.parsed_body
      expect(json["success"]).to be(false)
      expect(json["error"]).to eq("Resource not found")
      expect(json["code"]).to eq("NOT_FOUND")
    end
  end
end
