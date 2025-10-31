require 'rails_helper'

RSpec.describe "Calendars", type: :request do
  describe "GET /calendars/:calendar_token.ics" do
    let(:user) { User.create!(email: "test@example.com", calendar_token: "test-token-123") }
    
    context "when requesting ICS format" do
      before do
        get "/calendars/#{user.calendar_token}.ics"
      end

      it "returns success" do
        expect(response).to have_http_status(:success)
      end

      it "returns text/calendar content type" do
        expect(response.content_type).to match(/text\/calendar/)
      end

      it "sets Cache-Control header with 1 hour max-age" do
        expect(response.headers['Cache-Control']).to eq('max-age=3600, must-revalidate')
      end

      it "sets X-Published-TTL header for iCalendar refresh hint" do
        expect(response.headers['X-Published-TTL']).to eq('PT1H')
      end

      it "sets Refresh-Interval header" do
        expect(response.headers['Refresh-Interval']).to eq('3600')
      end
    end

    context "when calendar_token is invalid" do
      it "raises ActiveRecord::RecordNotFound" do
        expect {
          get "/calendars/invalid-token.ics"
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
