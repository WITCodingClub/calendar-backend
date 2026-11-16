# frozen_string_literal: true

# The lowest access level of each admin section. The admin navigation
# (Admin::NavigationRegistry), the policies, and the route constraints
# (AdminConstraint) all read it, so a page that the navigation hides is also
# closed by URL. A section that is not listed needs admin access.
# spec/policies/admin_access_spec.rb ties the three together.
module AdminAccess
  DEFAULT = :admin

  SECTIONS = {
    # Starts a Banner import of a whole term.
    course_catalog:  :super_admin,
    system_tools:    :super_admin,
    # The mounted tools can run jobs, change flags, and read any row.
    jobs:            :super_admin,
    feature_flags:   :super_admin,
    sql:             :super_admin,
    database:        :super_admin,
    # Shows the Rails console sessions of every maintainer.
    console_audits:  :owner,
    # Changes the Google account that the app acts as.
    service_account: :owner
  }.freeze

  module_function

  def min_role(section) = SECTIONS.fetch(section, DEFAULT)

  def allowed?(user, section = nil)
    user.present? && user.access_at_least?(min_role(section))
  end
end
