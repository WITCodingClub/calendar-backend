# Authorization Policies

This document describes the Pundit-based authorization system used throughout the application.

## Table of Contents
- [Overview](#overview)
- [Access Levels](#access-levels)
- [Policy Categories](#policy-categories)
- [Policy Rules](#policy-rules)
- [Using Policies in Controllers](#using-policies-in-controllers)
- [Policy List](#policy-list)

---

## Overview

The application uses [Pundit](https://github.com/varvet/pundit) for authorization. Pundit provides object-oriented authorization through policy classes that determine what actions users can perform on resources.

**Key Features:**
- Role-based access control via User `access_level` enum
- Granular permissions for different admin levels
- Protection against super_admins deleting owner accounts
- Separate policies for user-owned, public-read, and admin-only resources

---

## Access Levels

The User model has four access levels (defined in `app/models/user.rb`):

| Level | Value | Description |
|-------|-------|-------------|
| **user** | 0 | Regular user - can manage their own resources only |
| **admin** | 1 | Admin - can VIEW all resources for support, manage public data (courses/faculty), but CANNOT modify other users' resources or perform destructive actions |
| **super_admin** | 2 | Super admin - can view AND modify all resources, perform destructive actions (delete), access feature flags. **Cannot delete owners or owner-owned resources** |
| **owner** | 3 | Owner - full access to everything including managing other admins |

**Helper Methods (available in all policies):**
```ruby
admin?          # Returns true for admin, super_admin, or owner
super_admin?    # Returns true for super_admin or owner
owner?          # Returns true for owner only
```

---

## Policy Categories

### 1. User-Owned Resources

Resources that belong to individual users. Users can manage their own, admins can view all for support, and super_admins can modify all.

**Models:**
- User
- Email
- OauthCredential
- GoogleCalendar
- GoogleCalendarEvent
- Enrollment
- CalendarPreference
- EventPreference
- UserExtensionConfig

**Permission Pattern:**
```ruby
index?   # admin? - Admins can list all for support
show?    # owner_of_record? || admin? - Users see their own, admins see all
create?  # owner_of_record? || super_admin? - Users create their own, super_admins can create for others
update?  # owner_of_record? || super_admin? - Users update their own, super_admins can update others
destroy? # owner_of_record? || can_perform_destructive_action? - Users delete their own, super_admins can delete others (except owners)
```

**Special Case - User Model:**
- `create?` allows `admin?` (admins can create new user accounts)
- `destroy?` uses `can_perform_destructive_action?` which prevents super_admins from deleting owner accounts

---

### 2. Public-Read Resources

Resources that everyone can view, but only admins can manage.

**Models:**
- Course
- Faculty
- Term
- MeetingTime
- Building
- Room
- RmpRating
- RelatedProfessor
- RatingDistribution
- TeacherRatingTag

**Permission Pattern:**
```ruby
index?   # true - Everyone can list
show?    # true - Everyone can view
create?  # admin? - Admins can add content
update?  # admin? - Admins can edit content
destroy? # super_admin? - Only super_admins can delete (destructive)
```

---

### 3. Admin-Only Resources

System-generated records for auditing and analytics. Only admins can view, only super_admins can delete.

**Models:**
- LockboxAudit
- Ahoy::Visit
- Ahoy::Event
- Ahoy::Message

**Permission Pattern:**
```ruby
index?   # admin? - Only admins can list
show?    # admin? - Only admins can view
create?  # false - System-generated only
update?  # false - Immutable
destroy? # super_admin? - Only super_admins can delete for cleanup
```

---

## Policy Rules

### Owner Protection

The `can_perform_destructive_action?` helper method prevents super_admins from deleting owners or owner-owned resources:

```ruby
def can_perform_destructive_action?
  return false unless user

  # Determine the target user
  target_user = if record.is_a?(User)
    record
  elsif record.respond_to?(:user)
    record.user
  elsif record.respond_to?(:oauth_credential) && record.oauth_credential.respond_to?(:user)
    record.oauth_credential.user
  else
    nil
  end

  # If no target user, use super_admin? check
  return super_admin? unless target_user

  # If target is an owner, only an owner can perform destructive action
  if target_user.owner?
    owner?
  else
    super_admin?
  end
end
```

This ensures:
- Super admins can delete regular users and admin accounts
- Super admins **cannot** delete owner accounts or their resources
- Only owners can delete other owner accounts

---

## Using Policies in Controllers

### Basic Usage

```ruby
class CoursesController < ApplicationController
  before_action :authenticate_user!

  def index
    @courses = policy_scope(Course)
    # Returns all courses (public-read)
  end

  def show
    @course = Course.find(params[:id])
    authorize @course
    # Checks CoursePolicy#show? (everyone can view)
  end

  def create
    @course = Course.new(course_params)
    authorize @course
    # Checks CoursePolicy#create? (admin? required)

    if @course.save
      redirect_to @course
    else
      render :new
    end
  end

  def destroy
    @course = Course.find(params[:id])
    authorize @course
    # Checks CoursePolicy#destroy? (super_admin? required)

    @course.destroy
    redirect_to courses_path
  end
end
```

### Scopes

Use `policy_scope` to filter collections based on user permissions:

```ruby
# Returns only the current user's calendars for regular users,
# all calendars for admins
@calendars = policy_scope(GoogleCalendar)
```

### Manual Authorization Checks

```ruby
if policy(@user).update?
  # Show edit button
end
```

### Rescue Unauthorized

Pundit raises `Pundit::NotAuthorizedError` when authorization fails. Handle it in `ApplicationController`:

```ruby
class ApplicationController < ActionController::Base
  include Pundit::Authorization

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  private

  def user_not_authorized
    flash[:alert] = "You are not authorized to perform this action."
    redirect_to(request.referrer || root_path)
  end
end
```

---

## Policy List

### User-Owned Resources
| Model | Policy | Notes |
|-------|--------|-------|
| User | `UserPolicy` | Admins can create users |
| Email | `EmailPolicy` | - |
| OauthCredential | `OauthCredentialPolicy` | - |
| GoogleCalendar | `GoogleCalendarPolicy` | Ownership through `oauth_credential` |
| GoogleCalendarEvent | `GoogleCalendarEventPolicy` | Ownership through `google_calendar.oauth_credential` |
| Enrollment | `EnrollmentPolicy` | - |
| CalendarPreference | `CalendarPreferencePolicy` | - |
| EventPreference | `EventPreferencePolicy` | - |
| UserExtensionConfig | `UserExtensionConfigPolicy` | - |

### Public-Read Resources
| Model | Policy | Notes |
|-------|--------|-------|
| Course | `CoursePolicy` | - |
| Faculty | `FacultyPolicy` | - |
| Term | `TermPolicy` | - |
| MeetingTime | `MeetingTimePolicy` | - |
| Building | `BuildingPolicy` | - |
| Room | `RoomPolicy` | - |
| RmpRating | `RmpRatingPolicy` | Rate My Professor data |
| RelatedProfessor | `RelatedProfessorPolicy` | - |
| RatingDistribution | `RatingDistributionPolicy` | - |
| TeacherRatingTag | `TeacherRatingTagPolicy` | - |

### Admin-Only Resources
| Model | Policy | Notes |
|-------|--------|-------|
| LockboxAudit | `LockboxAuditPolicy` | Encryption audit logs |
| Ahoy::Visit | `Ahoy::VisitPolicy` | Analytics - visitor tracking |
| Ahoy::Event | `Ahoy::EventPolicy` | Analytics - event tracking |
| Ahoy::Message | `Ahoy::MessagePolicy` | Analytics - message tracking |

### Admin Policies
| Policy | Purpose |
|--------|---------|
| AdminPolicy | Controls access to admin tools (Blazer, Flipper, admin endpoints) |

---

## Testing Policies

Pundit provides RSpec matchers for testing policies:

```ruby
require 'rails_helper'

RSpec.describe CoursePolicy, type: :policy do
  subject { described_class }

  let(:regular_user) { create(:user, access_level: :user) }
  let(:admin_user) { create(:user, access_level: :admin) }
  let(:super_admin_user) { create(:user, access_level: :super_admin) }
  let(:owner_user) { create(:user, access_level: :owner) }
  let(:course) { create(:course) }

  permissions :index?, :show? do
    it "allows everyone to view courses" do
      expect(subject).to permit(regular_user, course)
      expect(subject).to permit(admin_user, course)
    end
  end

  permissions :create?, :update? do
    it "allows admins to manage courses" do
      expect(subject).to permit(admin_user, course)
      expect(subject).to permit(super_admin_user, course)
    end

    it "denies regular users from managing courses" do
      expect(subject).not_to permit(regular_user, course)
    end
  end

  permissions :destroy? do
    it "only allows super_admins to delete courses" do
      expect(subject).to permit(super_admin_user, course)
      expect(subject).to permit(owner_user, course)
    end

    it "denies admins and users from deleting courses" do
      expect(subject).not_to permit(admin_user, course)
      expect(subject).not_to permit(regular_user, course)
    end
  end
end
```

See `spec/policies/` for complete test examples.
