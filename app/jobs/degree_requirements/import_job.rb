# frozen_string_literal: true

module DegreeRequirements
  # Imports the programs of one catalog year (DegreeRequirements::Importer),
  # then queues the course import. `bin/rails degree_requirements:import`
  # queues it, and CurrentYearImportJob queues it each month.
  #
  # A year before 2019-2020 has only a PDF (PdfCatalog::Importer), and the
  # course search API does not have it. 2025-2026 reads the PDF after the
  # Wayback Machine, for the programs that the Wayback Machine does not have.
  class ImportJob < ApplicationJob
    CONCURRENCY_GROUP = "DegreeRequirementsImportJob"

    queue_as :low

    # One import at a time, for every year: two years write the same
    # DegreeProgram rows. A year is about 130 pages, half a second apart (5
    # seconds on the Wayback Machine), plus the retries of a slow site.
    limits_concurrency to: 1, group: CONCURRENCY_GROUP, key: ->(*) { "degree_requirements_import" }, duration: 1.hour

    retry_on FetchError, wait: :polynomially_longer, attempts: 3

    BATCH_DESCRIPTION = "Degree requirements import"

    # Queues the import of one year as a Solid Queue batch. The course import
    # that the job queues joins the same batch, so the batch ends when both
    # jobs have ended. Every caller uses this, not perform_later, or the admin
    # page does not show the year as importing.
    def self.enqueue_in_batch(start_year, force: false)
      SolidQueue::Batch.enqueue(description: BATCH_DESCRIPTION, start_year: start_year) do
        perform_later(start_year, force: force)
      end
    end

    # The start years with an import of programs or courses in the queue or
    # running. The admin page of the catalog years shows them as importing,
    # until the course import that this job queues has finished too. A batch
    # with a failed job is finished, so a failed import does not count.
    def self.queued_start_years
      batched = SolidQueue::Batch.where(description: BATCH_DESCRIPTION, finished_at: nil)
                                 .filter_map { |batch| Integer(batch.metadata[:start_year], exception: false) }
      batched.to_set | unbatched_start_years
    end

    # Jobs with no batch: queued before enqueue_in_batch existed, or a course
    # import whose batch had finished (enqueue_course_import). Remove the
    # first case when production has no such ImportJob left.
    def self.unbatched_start_years
      SolidQueue::Job.where(class_name: [ name, CourseImportJob.name ], finished_at: nil, batch_id: nil)
                     .where.missing(:failed_execution)
                     .pluck(:arguments)
                     .filter_map { |job| Integer(job["arguments"]&.first, exception: false) if job.is_a?(Hash) }
    end
    private_class_method :unbatched_start_years

    def perform(start_year, force: false)
      catalog_year = CatalogYear.find_or_create_by!(start_year: start_year)
      return PdfCatalog::Importer.new(catalog_year).call if PdfCatalog.pdf_only?(start_year)

      result = Importer.new(catalog_year, force: force).call
      if result.status == :imported
        enqueue_course_import(start_year)
        fill_from_pdf(catalog_year) if PdfCatalog::FILES.key?(start_year)
      end
      result
    rescue StandardError
      # A year with stored data keeps its status. The executor reports the
      # error, and the data from the last import is still good.
      catalog_year.update_columns(status: "failed") if catalog_year && !catalog_year.requirement_sets.exists?
      raise
    end

    private

    # Inside the batch, the course import joins it. A job queued with
    # perform_later has no batch. A failed import that someone retried from
    # Mission Control keeps its batch, but that batch finished when the job
    # failed and takes no new job, so the course import goes on its own.
    def enqueue_course_import(start_year)
      if batch && !batch.finished?
        batch.enqueue { CourseImportJob.perform_later(start_year) }
      else
        CourseImportJob.perform_later(start_year)
      end
    rescue SolidQueue::Batch::AlreadyFinished
      CourseImportJob.perform_later(start_year)
    end

    # The PDF only adds programs to a year the site already imported. Its
    # failure is reported and the HTML data stays, so a bad PDF does not
    # retry the whole Wayback import.
    def fill_from_pdf(catalog_year)
      PdfCatalog::Importer.new(catalog_year).call
    rescue StandardError => e
      Rails.error.report(e, handled: true, context: { catalog_year_id: catalog_year.id })
    end
  end
end
