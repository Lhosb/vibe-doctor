# Vibe Doctor — Copilot Instructions

Follow these rules for all generated or edited code in this repository.

## Stack context

- Rails 8.1 with Ruby 3.x
- PostgreSQL
- Hotwire (Turbo + Stimulus)
- Import Maps
- Solid Queue / Active Job
- Tailwind CSS
- RSpec + FactoryBot + Capybara + WebMock

## Architecture rules (required)

- Keep domain and business logic in models when it is model-related.
- `app/services` is only for external integrations and external I/O boundaries (APIs, SDK wrappers, transport clients).
- Do not introduce internal service objects for model/domain behavior that belongs in `app/models`.
- Keep controllers thin: auth, params, flow control, response rendering.
- Keep jobs orchestration-focused and idempotent; do not bury domain policy in jobs.

## Ruby and Rails standards

- Prefer idiomatic Rails conventions over custom patterns.
- Prefer practical OOP: cohesive classes, small public APIs, clear method names.
- Apply DRY pragmatically; extract only when reuse/clarity is real.
- Prefer modern Ruby keyword shorthand when names match (`call(user:)` not `call(user: user)`).
- Use explicit failure semantics (`save!`, `update!`, `find_or_create_by!`) where data integrity matters.
- Keep callbacks minimal; prefer explicit model methods for important state changes.

## Data integrity and querying

- Enforce invariants in both model validations and database constraints/indexes.
- Use transactions for atomic multi-write operations.
- Prevent N+1 queries with `includes`/`preload` and relation-based composition.
- Prefer scopes for reusable query intent that returns `ActiveRecord::Relation`.

## Hotwire + Importmap expectations

- Use Turbo for navigation and partial page updates before adding custom JavaScript.
- Use Stimulus for behavior; keep controllers single-purpose with explicit targets/actions/values.
- Prefer declarative `data-action` and target accessors over manual DOM querying.
- Keep JavaScript modular under `app/javascript/controllers` and aligned with importmap usage.

## Background jobs (Solid Queue)

- Use dedicated job classes inheriting from `ApplicationJob`.
- Use clear queue names and explicit retry/discard behavior when needed.
- Ensure jobs are safe to run more than once when feasible.
- Push domain transitions into models; jobs should orchestrate, not own business policy.

## Testing rules

- Add/update RSpec tests with behavior changes.
- Model rules belong in model specs.
- Request/system behavior belongs in request/system specs.
- Stub external HTTP/network interactions (WebMock).

## Scoped instruction files

Use these specialized instruction files for context-specific guidance:

- `.github/instructions/rails-architecture.instructions.md`
- `.github/instructions/hotwire-importmap.instructions.md`
- `.github/instructions/solid-queue.instructions.md`
