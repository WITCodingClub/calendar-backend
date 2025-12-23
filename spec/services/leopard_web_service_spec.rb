# frozen_string_literal: true

require "rails_helper"

RSpec.describe LeopardWebService, type: :service do
  describe ".get_course_catalog" do
    let(:term) { "202620" }

    context "when fetching courses successfully" do
      it "initializes session and fetches courses" do
        # Mock session initialization response
        session_response = double(
          success?: true,
          headers: { "set-cookie" => "JSESSIONID=abc123; Path=/; HttpOnly" }
        )

        # Mock catalog response
        catalog_response = double(
          success?: true,
          body: {
            "data" => [
              { "courseReferenceNumber" => "12345", "courseTitle" => "Test Course" }
            ],
            "totalCount" => 1
          }
        )

        mock_session_connection = double
        mock_catalog_connection = double

        allow(mock_session_connection).to receive(:post).and_yield(double(params: {}, body: nil).as_null_object).and_return(session_response)
        allow(mock_catalog_connection).to receive(:get).and_return(catalog_response)

        service = described_class.new(action: :get_course_catalog, term: term)

        allow(service).to receive(:session_connection).and_return(mock_session_connection)
        # Set the session cookie manually since we're mocking
        service.instance_variable_set(:@session_cookie, "abc123")
        allow(service).to receive(:catalog_connection).and_return(mock_catalog_connection)

        result = service.call

        expect(result[:success]).to be true
        expect(result[:courses].length).to eq(1)
        expect(result[:total_count]).to eq(1)
      end

      it "handles pagination correctly" do
        # Mock session initialization response
        session_response = double(
          success?: true,
          headers: { "set-cookie" => "JSESSIONID=abc123; Path=/; HttpOnly" }
        )

        # First page
        first_response = double(
          success?: true,
          body: {
            "data" => Array.new(500) { |i| { "courseReferenceNumber" => i.to_s } },
            "totalCount" => 750
          }
        )

        # Second page
        second_response = double(
          success?: true,
          body: {
            "data" => Array.new(250) { |i| { "courseReferenceNumber" => (i + 500).to_s } },
            "totalCount" => 750
          }
        )

        mock_session_connection = double
        mock_catalog_connection = double

        allow(mock_session_connection).to receive(:post).and_yield(double(params: {}, body: nil).as_null_object).and_return(session_response)
        allow(mock_catalog_connection).to receive(:get).and_return(first_response, second_response)

        service = described_class.new(action: :get_course_catalog, term: term)

        allow(service).to receive(:session_connection).and_return(mock_session_connection)
        service.instance_variable_set(:@session_cookie, "abc123")
        allow(service).to receive(:catalog_connection).and_return(mock_catalog_connection)

        result = service.call

        expect(result[:success]).to be true
        expect(result[:courses].length).to eq(750)
        expect(result[:total_count]).to eq(750)
      end
    end

    context "when session initialization fails" do
      it "returns error information" do
        session_response = double(
          success?: false,
          status: 500
        )

        mock_session_connection = double
        allow(mock_session_connection).to receive(:post).and_yield(double(params: {}, body: nil).as_null_object).and_return(session_response)

        service = described_class.new(action: :get_course_catalog, term: term)
        allow(service).to receive(:session_connection).and_return(mock_session_connection)

        result = service.call

        expect(result[:success]).to be false
        expect(result[:error]).to include("Failed to initialize search session")
        expect(result[:courses]).to eq([])
        expect(result[:total_count]).to eq(0)
      end
    end

    context "when no session cookie is returned" do
      it "returns error information" do
        session_response = double(
          success?: true,
          headers: {} # No set-cookie header
        )

        mock_session_connection = double
        allow(mock_session_connection).to receive(:post).and_yield(double(params: {}, body: nil).as_null_object).and_return(session_response)

        service = described_class.new(action: :get_course_catalog, term: term)
        allow(service).to receive(:session_connection).and_return(mock_session_connection)

        result = service.call

        expect(result[:success]).to be false
        expect(result[:error]).to include("Failed to obtain session cookie")
        expect(result[:courses]).to eq([])
        expect(result[:total_count]).to eq(0)
      end
    end

    context "when catalog request fails" do
      it "returns error information" do
        session_response = double(
          success?: true,
          headers: { "set-cookie" => "JSESSIONID=abc123; Path=/; HttpOnly" }
        )

        catalog_response = double(
          success?: false,
          status: 401,
          body: "Unauthorized"
        )

        mock_session_connection = double
        mock_catalog_connection = double

        allow(mock_session_connection).to receive(:post).and_yield(double(params: {}, body: nil).as_null_object).and_return(session_response)
        allow(mock_catalog_connection).to receive(:get).and_return(catalog_response)

        service = described_class.new(action: :get_course_catalog, term: term)

        allow(service).to receive(:session_connection).and_return(mock_session_connection)
        service.instance_variable_set(:@session_cookie, "abc123")
        allow(service).to receive(:catalog_connection).and_return(mock_catalog_connection)

        result = service.call

        expect(result[:success]).to be false
        expect(result[:error]).to include("401")
        expect(result[:courses]).to eq([])
        expect(result[:total_count]).to eq(0)
      end
    end

    context "validation" do
      it "raises error when term is missing" do
        expect {
          described_class.get_course_catalog(term: nil)
        }.to raise_error(ArgumentError, /term is required/)
      end
    end
  end

  describe "#initialize_search_session!" do
    let(:term) { "202620" }

    it "extracts JSESSIONID from response cookies" do
      session_response = double(
        success?: true,
        headers: { "set-cookie" => "JSESSIONID=my_session_123; Path=/; HttpOnly" }
      )

      mock_connection = double
      allow(mock_connection).to receive(:post).and_yield(double(params: {}, body: nil).as_null_object).and_return(session_response)

      service = described_class.new(action: :get_course_catalog, term: term)
      allow(service).to receive(:session_connection).and_return(mock_connection)

      result = service.send(:initialize_search_session!)

      expect(result).to eq("my_session_123")
    end
  end
end
