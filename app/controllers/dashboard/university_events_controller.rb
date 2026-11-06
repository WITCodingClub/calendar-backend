# frozen_string_literal: true

module Dashboard
  # The university calendar, read-only (#797): holidays, term dates,
  # registration, deadlines, finals, and campus events. Upcoming events by
  # default, past=1 for the ones that are over.
  class UniversityEventsController < Dashboard::ApplicationController
    include CatalogPages

    def index
      authorize UniversityCalendarEvent

      @query    = params[:q].to_s.strip
      @past     = params[:past].to_s == "1"
      @category = params[:category].to_s.presence_in(UniversityCalendarEvent::CATEGORIES)
      @events   = Catalog::UniversityEventQuery.new.call(past: @past, category: @category, q: @query)
                                               .page(page_param).per(CatalogPages::PER_PAGE)
    end
  end
end
