# frozen_string_literal: true

# Gates the admin tools that can run jobs, change feature flags, read any
# database row, or show console sessions. Admin access is not enough for these.
class SuperAdminConstraint
  def matches?(request)
    user = request.env["warden"]&.user
    user.present? && user.super_admin_access?
  end
end
