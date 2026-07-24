---
applyTo: "**/*.rb"
---
# Rails Architecture and Ruby Standards

## Required architecture constraints

- Keep model-related business logic in models.
- Use `app/services` only for external integrations (third-party APIs, SDKs, transport boundaries).
- Do not move internal domain logic into service objects.
- Keep controllers focused on HTTP concerns and flow.
- Keep jobs orchestration-focused; model rules stay in model methods.

## Ruby style and object design

- Use clear, intention-revealing method names and small public APIs.
- Favor practical OOP and high cohesion over deep inheritance and indirection.
- Apply DRY pragmatically; avoid speculative abstraction.
- Use guard clauses to reduce nested control flow.
- Prefer keyword arg shorthand when names match (`foo(bar:)`).

## Active Record best practices

- Put invariants in validations and back them with database constraints.
- Use custom error types for invalid state transitions.
- Use transactions for atomic multi-write changes.
- Use scopes for reusable query intent.
- Prevent N+1 queries with eager loading.

## Error handling

- Fail explicitly when writes are required to succeed (`save!`, `update!`).
- Do not silently rescue external or persistence errors.
