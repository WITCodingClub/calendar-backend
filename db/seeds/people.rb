# frozen_string_literal: true

module Seeds
  # Fake people for a development database. The catalog snapshot holds no
  # student records, so students, enrollments, and friendships come from
  # factories, over the real courses of the most recent term.
  #
  # Every account signs in with the factory password, "password123".
  class People
    ADMIN_EMAIL = "admin@example.com"

    def self.call(...) = new(...).call

    def initialize(count: 40, courses_per_student: 4..6, seed: 2026)
      @count = count
      @courses_per_student = courses_per_student
      @seed = seed
      @random = Random.new(seed)
    end

    def call
      courses = Course.active.where(term: Term.where(id: Course.select(:term_id)).order(uid: :desc).first).to_a
      return [] if courses.empty?

      # A fixed seed gives the same names on every run. Faker's random is global.
      Faker::Config.random = Random.new(@seed)
      admin = FactoryBot.create(:user, :admin, email: ADMIN_EMAIL)
      students = Array.new(@count) { |i| FactoryBot.create(:user, email: "student#{i + 1}@example.com") }

      [ admin, *students ].each { |user| enroll(user, courses) }
      # Accepted, because a pending request emails the addressee.
      students.each_slice(2) { |requester, addressee| FactoryBot.create(:friendship, :accepted, requester: requester, addressee: addressee) if addressee }

      [ admin, *students ]
    ensure
      Faker::Config.random = nil
    end

    private

    def enroll(user, courses)
      courses.sample(@random.rand(@courses_per_student), random: @random).each do |course|
        FactoryBot.create(:enrollment, user: user, course: course)
      end
    end
  end
end
