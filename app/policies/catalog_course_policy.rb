# frozen_string_literal: true

# The course catalog is public: GET /api/v1/catalog/courses needs no token.
# The dashboard shows it to every signed-in user (#797).
class CatalogCoursePolicy < PublicRecordPolicy
  def index? = user.present?
  def show?  = user.present?
end
