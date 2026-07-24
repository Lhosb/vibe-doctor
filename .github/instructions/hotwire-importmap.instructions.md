---
applyTo: "app/views/**/*.erb,app/javascript/**/*.js"
---
# Hotwire and Importmap Guidelines

## Turbo-first UI behavior

- Prefer Turbo Drive/Frames/Streams for dynamic updates before custom JS.
- Use semantic, server-rendered HTML as the baseline.
- Keep progressive enhancement: pages should remain usable without JS where practical.

## Stimulus controller standards

- One clear responsibility per controller.
- Use descriptive controller, target, and action names.
- Prefer declarative actions (`data-action="controller#method"`).
- Use Stimulus targets/values APIs instead of ad hoc selectors when possible.
- Keep action methods small and focused on UI behavior.

## Turbo + Stimulus integration

- Let Turbo handle navigation and replacement; Stimulus handles behavior.
- Make controllers resilient to connect/disconnect cycles caused by Turbo navigation.
- Avoid duplicate listeners and leaked state across visits.

## Importmap usage

- Keep JS dependencies pinned in `config/importmap.rb`.
- Keep controller modules under `app/javascript/controllers`.
- Prefer small, composable modules over large page scripts.
