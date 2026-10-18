# frozen_string_literal: true

require "rails_helper"

# Issue #702: every layout declares its language, charset, and browser
# toolbar colors, and the dashboard sends the CSRF token once.
RSpec.describe "Head metadata", type: :request do
  let(:page) { Nokogiri::HTML(response.body) }

  shared_examples "a complete head" do |light:, dark:|
    it "declares the language and charset" do
      expect(page.at_css("html")["lang"]).to eq("en")
      expect(page.at_css("head meta[charset]")["charset"]).to eq("utf-8")
    end

    it "sets the color scheme and a theme color for each scheme" do
      expect(page.at_css("meta[name='color-scheme']")["content"]).to eq("light dark")

      colors = page.css("meta[name='theme-color']").to_h { |meta| [ meta["media"], meta["content"] ] }
      expect(colors).to eq(
        "(prefers-color-scheme: light)" => light,
        "(prefers-color-scheme: dark)" => dark
      )
    end

    it "sends one CSRF token" do
      expect(page.css("meta[name='csrf-token']").size).to be <= 1
    end
  end

  describe "application layout" do
    # No route renders this layout today, so render it the way a bare controller would.
    let(:page) { Nokogiri::HTML(ApplicationController.render(html: "", layout: "application")) }

    it_behaves_like "a complete head", light: "#fff8f1", dark: "#16130b"

    it "does not claim web app support without a manifest" do
      expect(page.at_css("meta[name='mobile-web-app-capable']")).to be_nil
      expect(page.at_css("meta[name='apple-mobile-web-app-capable']")).to be_nil
    end
  end

  describe "sessions layout" do
    before { get new_user_session_path }

    it_behaves_like "a complete head", light: "#fff8f1", dark: "#16130b"
  end

  describe "public layout" do
    before { get "/meet/#{create(:meeting_link).token}" }

    it_behaves_like "a complete head", light: "#fff8f1", dark: "#16130b"
  end

  describe "dashboard layout" do
    before do
      sign_in create(:user, :with_processed_courses)
      get dashboard_schedule_path
    end

    it_behaves_like "a complete head", light: "#fff8f1", dark: "#16130b"

    context "with forgery protection on" do
      # The test environment turns it off, and then csrf_meta_tags renders nothing.
      around do |example|
        ActionController::Base.allow_forgery_protection = true
        example.run
      ensure
        ActionController::Base.allow_forgery_protection = false
      end

      it "sends exactly one CSRF token" do
        expect(page.css("meta[name='csrf-token']").size).to eq(1)
      end
    end

    it "truncates a long title in the mobile top bar" do
      title = page.at_css("header.lg\\:hidden span.font-bold")

      expect(title["class"].split).to include("truncate")
      expect(title.parent["class"].split).to include("min-w-0")
    end
  end

  describe "admin layout" do
    before do
      stub_request(:get, "https://api.github.com/repos/WITCodingClub/calendar/releases/latest")
        .to_return(status: 200, body: { tag_name: "v0.0.0" }.to_json)
      allow(TwentyFiveLive::SyncJob).to receive(:in_progress?).and_return(false)
      sign_in create(:user, :admin)
      get admin_buildings_path
    end

    it_behaves_like "a complete head", light: "#fff8f1", dark: "#16130b"
  end
end
