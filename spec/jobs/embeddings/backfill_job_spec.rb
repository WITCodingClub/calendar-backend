# frozen_string_literal: true

require "rails_helper"

RSpec.describe Embeddings::BackfillJob, :embeddings do
  include ActiveJob::TestHelper

  it "queues a batch job for the records that need a vector" do
    course = create(:catalog_course)

    expect { described_class.perform_now("CatalogCourse") }
      .to have_enqueued_job(Embeddings::GenerateJob).with("CatalogCourse", [ course.id ])
  end

  it "queues nothing when every record is current" do
    give_embedding(create(:catalog_course), 0.25)

    expect { described_class.perform_now("CatalogCourse") }.not_to have_enqueued_job(Embeddings::GenerateJob)
  end

  it "queues a course again when its catalog year description changes" do
    course = give_embedding(create(:catalog_course, description: nil), 0.25)
    create(:catalog_year_course, subject_code: course.subject_code, course_number: course.course_number,
                                 description: "Sorting and searching.")
    CatalogYearCourse.link_catalog_courses

    expect { described_class.perform_now("CatalogCourse") }
      .to have_enqueued_job(Embeddings::GenerateJob).with("CatalogCourse", [ course.id ])
  end

  it "leaves out reviews with no comment" do
    faculty = create(:faculty)
    create(:rmp_rating, faculty: faculty, comment: nil)

    expect { described_class.perform_now("RmpRating") }.not_to have_enqueued_job(Embeddings::GenerateJob)
  end

  it "covers every model when it is given none" do
    create(:catalog_course)

    expect { described_class.perform_now }.to have_enqueued_job(Embeddings::GenerateJob).with("CatalogCourse", anything)
  end

  it "queues nothing without an API key" do
    create(:catalog_course)
    ENV.delete("OPENAI_API_KEY")

    expect { described_class.perform_now }.not_to have_enqueued_job(Embeddings::GenerateJob)
  end

  it "raises for a model it does not own" do
    expect { described_class.perform_now("User") }.to raise_error(ArgumentError, /Unknown model/)
  end
end
