class Admin::CalendarsController < Admin::BaseController
  def index
    @calendars = GoogleCalendarService.new.list_calendars.items
  end

  def destroy
    begin
      GoogleCalendarService.new.delete_calendar(params[:id])
      redirect_to admin_calendars_path, notice: "Calendar deleted successfully."
    rescue Google::Apis::ClientError => e
      redirect_to admin_calendars_path, alert: "Failed to delete calendar: #{e.message}"
    end
  end
end
