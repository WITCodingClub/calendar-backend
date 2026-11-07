# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::CatalogYears", type: :request do
  let(:admin) { create(:user, :admin) }

  before do
    stub_request(:get, "https://api.github.com/repos/WITCodingClub/calendar/releases/latest")
      .to_return(status: 200, body: { tag_name: "v0.0.0" }.to_json)
    allow(TwentyFiveLive::SyncJob).to receive(:in_progress?).and_return(false)
    sign_in admin
  end

  describe "GET /admin/catalog_years" do
    it "lists stored years with their source, status, and counts, and the HTML years not imported yet" do
      catalog_year = create(:catalog_year, :imported, start_year: 2024, source: "wayback")
      create(:requirement_set, catalog_year: catalog_year)
      create(:catalog_year, start_year: 2013, source: "pdf", status: "failed")

      get admin_catalog_years_path

      expect(response).to have_http_status(:ok)
      row = Nokogiri::HTML(response.body).css("#catalog-years-table tbody tr").find { |tr| tr.text.include?("2024-2025") }
      expect(row.text).to include("Wayback", "Imported")
      expect(response.body).to include("2019-2020", "Not imported", "2013-2014", "Failed")
    end

    it "shows a year with an import in the queue as importing, with no button" do
      job = DegreeRequirements::ImportJob.new(2024)
      SolidQueue::Job.create!(class_name: job.class.name, queue_name: "low", active_job_id: job.job_id, arguments: job.serialize)

      get admin_catalog_years_path

      row = Nokogiri::HTML(response.body).css("#catalog-years-table tbody tr").find { |tr| tr.text.include?("2024-2025") }
      expect(row.css("button[disabled]").map(&:text)).to eq([ "Importing…" ])
    end

    it "shows no import button for a PDF year" do
      create(:catalog_year, :from_pdf, start_year: 2013)

      get admin_catalog_years_path

      row = Nokogiri::HTML(response.body).css("#catalog-years-table tbody tr").find { |tr| tr.text.include?("2013-2014") }
      expect(row.css("button")).to be_empty
    end

    it "links to the background jobs only for a super admin, who can open them" do
      get admin_catalog_years_path
      expect(response.body).not_to include("shows the job status")

      sign_in create(:user, access_level: :super_admin)
      get admin_catalog_years_path
      expect(response.body).to include("shows the job status")
    end

    it "sends a user without admin access away" do
      sign_in create(:user)

      get admin_catalog_years_path

      expect(response).not_to have_http_status(:ok)
    end
  end

  describe "POST /admin/catalog_years/:id/import" do
    it "queues the import of one year" do
      expect { post import_admin_catalog_year_path(2024) }
        .to have_enqueued_job(DegreeRequirements::ImportJob).with(2024, force: false)

      expect(response).to redirect_to(admin_catalog_years_path)
      expect(flash[:notice]).to eq("Queued the import of 2024-2025.")
    end

    it "passes force on" do
      expect { post import_admin_catalog_year_path(2024, force: 1) }
        .to have_enqueued_job(DegreeRequirements::ImportJob).with(2024, force: true)
    end

    it "refuses a year outside the HTML catalog years" do
      expect { post import_admin_catalog_year_path(2015) }.not_to have_enqueued_job(DegreeRequirements::ImportJob)
      expect { post import_admin_catalog_year_path("x") }.not_to have_enqueued_job(DegreeRequirements::ImportJob)

      expect(flash[:alert]).to start_with("The import reads catalog years from 2019")
    end

    it "refuses a PDF year" do
      create(:catalog_year, :from_pdf, start_year: 2019)

      expect { post import_admin_catalog_year_path(2019) }.not_to have_enqueued_job(DegreeRequirements::ImportJob)
      expect(flash[:alert]).to include("comes from a PDF")
    end

    it "refuses a year with an import in the queue" do
      job = DegreeRequirements::ImportJob.new(2024)
      SolidQueue::Job.create!(class_name: job.class.name, queue_name: "low", active_job_id: job.job_id, arguments: job.serialize)

      expect { post import_admin_catalog_year_path(2024) }.not_to have_enqueued_job(DegreeRequirements::ImportJob)
      expect(flash[:alert]).to eq("An import of 2024-2025 is already in the queue.")
    end
  end

  describe "GET /admin/catalog_years/:id" do
    it "lists the programs of the year" do
      catalog_year = create(:catalog_year, :imported, start_year: 2024)
      set = create(:requirement_set, catalog_year: catalog_year, name: "Computer Science, B.S.", needs_review: true)
      create(:program_plan, requirement_set: set)

      get admin_catalog_year_path(2024)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Computer Science, B.S.", "Needs review")
      expect(response.body).to include(admin_degree_program_path(set.degree_program.slug, year: 2024))
    end

    it "answers a search given as an array" do
      create(:catalog_year, :imported, start_year: 2024)

      get admin_catalog_year_path(2024, search: [ "x" ])

      expect(response).to have_http_status(:ok)
    end

    it "answers 404 for a year that is not stored" do
      get admin_catalog_year_path(1999)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /admin/catalog_years/:id/course_comparison" do
    let!(:catalog_year) { create(:catalog_year, :imported, start_year: 2024) }

    before do
      create(:catalog_year_course, catalog_year: catalog_year, subject_code: "COMP", course_number: 1000, title: "CATALOG ONLY COURSE")
      create(:catalog_year_course, catalog_year: catalog_year, subject_code: "COMP", course_number: 2000, title: "OPERATING SYSTEMS")
      create(:catalog_course, subject_code: "COMP", course_number: 2000, title: "Intro to Operating Systems")
    end

    it "shows the courses that only the catalog has by default, and the count of each list" do
      get course_comparison_admin_catalog_year_path(2024)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("COMP 1000", "CATALOG ONLY COURSE")
      expect(response.body).not_to include("Intro to Operating Systems")
    end

    it "shows one list" do
      get course_comparison_admin_catalog_year_path(2024, kind: "title_differs")

      expect(response.body).to include("OPERATING SYSTEMS", "Intro to Operating Systems")
      expect(response.body).not_to include("CATALOG ONLY COURSE")
    end
  end
end
