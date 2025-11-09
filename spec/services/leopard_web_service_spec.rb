# frozen_string_literal: true

require "rails_helper"

RSpec.describe LeopardWebService, type: :service do
  describe ".get_course_catalog" do
    let(:term) { "202620" }
    let(:jsessionid) { "test_session_id" }
    let(:idmsessid) { "test_idm_session_id" }

    context "when all parameters are provided" do
      it "fetches courses successfully" do
        # Mock Faraday response
        mock_response = double(
          success?: true,
          body: {
            "data" => [
              { "courseReferenceNumber" => "12345", "courseTitle" => "Test Course" }
            ],
            "totalCount" => 1
          }
        )

        # Mock the connection
        mock_connection = double
        allow(mock_connection).to receive(:get).and_return(mock_response)

        service = described_class.new(
          action: :get_course_catalog,
          term: term,
          jsessionid: jsessionid,
          idmsessid: idmsessid
        )

        allow(service).to receive(:authenticated_connection).and_return(mock_connection)

        result = service.call

        expect(result[:success]).to be true
        expect(result[:courses].length).to eq(1)
        expect(result[:total_count]).to eq(1)
      end

      it "handles pagination correctly" do
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

        mock_connection = double
        allow(mock_connection).to receive(:get).and_return(first_response, second_response)

        service = described_class.new(
          action: :get_course_catalog,
          term: term,
          jsessionid: jsessionid,
          idmsessid: idmsessid
        )

        allow(service).to receive(:authenticated_connection).and_return(mock_connection)

        result = service.call

        expect(result[:success]).to be true
        expect(result[:courses].length).to eq(750)
        expect(result[:total_count]).to eq(750)
      end
    end

    context "when request fails" do
      it "returns error information" do
        mock_response = double(
          success?: false,
          status: 401,
          body: "Unauthorized"
        )

        mock_connection = double
        allow(mock_connection).to receive(:get).and_return(mock_response)

        service = described_class.new(
          action: :get_course_catalog,
          term: term,
          jsessionid: jsessionid,
          idmsessid: idmsessid
        )

        allow(service).to receive(:authenticated_connection).and_return(mock_connection)

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
          described_class.get_course_catalog(
            term: nil,
            jsessionid: jsessionid,
            idmsessid: idmsessid
          )
        }.to raise_error(ArgumentError, /term is required/)
      end

      it "raises error when jsessionid is missing" do
        expect {
          described_class.get_course_catalog(
            term: term,
            jsessionid: nil,
            idmsessid: idmsessid
          )
        }.to raise_error(ArgumentError, /jsessionid is required/)
      end

      it "raises error when idmsessid is missing" do
        expect {
          described_class.get_course_catalog(
            term: term,
            jsessionid: jsessionid,
            idmsessid: nil
          )
        }.to raise_error(ArgumentError, /idmsessid is required/)
      end
    end
  end
end
