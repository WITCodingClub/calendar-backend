# frozen_string_literal: true

class AdminMailer < ApplicationMailer
  default from: "WIT Calendar <noreply@wit.edu>"

  def missing_rmp_ids_summary(email:)
    @faculties = Faculty.where(rmp_id: nil).order(:last_name, :first_name).includes(:courses)
    @count = @faculties.count

    return if @count.zero?

    mail(
      to: email,
      subject: "Weekly Summary: #{@count} Faculty Missing RMP IDs"
    )
  end
end
