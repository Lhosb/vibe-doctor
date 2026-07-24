---
applyTo: "app/jobs/**/*job.rb,config/queue.yml,config/recurring.yml"
---
# Solid Queue and Active Job Guidelines

## Job design

- Jobs should orchestrate work, not own domain policy.
- Move state transitions and business rules into models.
- Keep jobs idempotent when possible (safe to retry/re-run).
- Use explicit queue names and priority by business urgency.

## Reliability and retries

- Use `retry_on` and `discard_on` intentionally for known failure classes.
- Surface hard failures clearly; avoid broad rescue blocks.
- For external API work, isolate transport concerns in external clients in `app/services`.

## Queue configuration

- Keep queue configuration in `config/queue.yml` aligned to workload priorities.
- Keep recurring/scheduled work in `config/recurring.yml`.
- Revisit polling intervals, threads, and processes when workload changes.

## Data consistency

- Use transactions where a job performs coupled multi-write updates.
- Enqueue dependent jobs after commit when the job requires persisted state.
