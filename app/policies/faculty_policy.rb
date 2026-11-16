# frozen_string_literal: true

class FacultyPolicy < PublicRecordPolicy
  def search_rmp?       = super_admin?
  def assign_rmp_id?    = super_admin?
  def auto_fill_rmp_id? = super_admin?
  def batch_auto_fill?  = super_admin?
  def missing_rmp_ids?  = admin?
  def sync_directory?   = super_admin?
  def directory_status? = admin?
end
