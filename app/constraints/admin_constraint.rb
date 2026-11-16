# frozen_string_literal: true

# Lets a request through when the signed-in user may open the admin section
# (AdminAccess). With no section, it needs admin access.
class AdminConstraint
  attr_reader :section

  def initialize(section = nil)
    @section = section
  end

  def matches?(request)
    AdminAccess.allowed?(request.env["warden"]&.user, section)
  end
end
