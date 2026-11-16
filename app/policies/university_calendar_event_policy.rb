# frozen_string_literal: true

class UniversityCalendarEventPolicy < PublicRecordPolicy
  def sync?     = admin?
  def backfill? = admin?
end
