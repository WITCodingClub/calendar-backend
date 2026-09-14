# CLAUDE.md

Rails 8 app that scrapes WIT course data and syncs it to Google Calendar. Specs use RSpec.

## Specs

### Test data

- Build records with factory_bot: `create(:course, term: term)`, `build(:user)`, `create_list(:enrollment, 3)`. Factories live in `spec/factories/`, one file per model.
- Pass only the attributes the example reads or asserts on. The factory fills the rest.
- In factories, use Faker for values no example checks, and `sequence` for unique columns.
- When the same attribute set repeats across specs, add a trait (`create(:user, :unconfirmed)`).
- `spec/factories_spec.rb` builds and saves every factory and trait. A new factory or trait must pass it.
- Migration specs in `spec/migrations/` build rows by hand, because factories follow today's models, not the schema at the migration. Records owned by gems, such as `SolidQueue::Job`, are also built by hand.

### Model specs

- Cover every association, validation, and enum that the model declares with shoulda-matchers one-liners: `it { is_expected.to belong_to(:term) }`.
- `validate_uniqueness_of` needs a saved subject: `subject { create(:course) }`.
- A cross-field or custom validation gets a normal example, with a comment that says why no matcher covers it.

### Fixture leakage

A spec that declares `fixtures :buildings` inserts those rows outside the test transaction, so they stay for the rest of the run. Buildings have unique `name` and `abbreviation` columns. Give buildings in a spec names and abbreviations that `spec/fixtures/buildings.yml` does not use. The building factory uses `FCT` names for this reason. A spec that fails only in the full run usually hits this.

### Running specs

- The test database connection comes from `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_USER`, and `POSTGRES_PASSWORD`.
- Set `HASHID_SALT` to any value. Without it, boot reads credentials and needs `config/master.key`.
- In a new worktree, run `bin/rails tailwindcss:build` first. Request specs fail without the built CSS.
- `bin/rails db:test:prepare && bundle exec rspec`
