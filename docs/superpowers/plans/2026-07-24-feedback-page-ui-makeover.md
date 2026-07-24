# Feedback Page UI Makeover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the `/feedback` page (heading + card + empty state) with Tailwind utilities to match the rest of the app, with zero behavior change.

**Architecture:** Pure view-layer edit. Add a page `<h1>` to `app/views/feedback/index.html.erb` and add Tailwind utility classes to `app/views/feedback/_card.html.erb`, reusing the bordered/rounded/muted-background card pattern already established by the Recommend page's result panel (`app/javascript/controllers/recommend_controller.js#renderResult`). No controller, model, Stimulus, or Turbo Stream changes.

**Tech Stack:** Rails 8.1 ERB views, Tailwind (utility classes, no new CSS files), RSpec (request + system specs already in place).

## Global Constraints

- This is a pure visual restyle: no changes to `FeedbackController`, `RecommendationEvent`, `app/views/feedback/create.turbo_stream.erb`, or `app/javascript/controllers/feedback_controller.js`.
- All `data-*` attributes on the card's root div and buttons stay byte-for-byte identical (`data-controller="feedback"`, `data-feedback-event-id-value="<%= event.id %>"`, `data-action="feedback#choose"`, `data-feedback-outcome-param="good"|"bad"|"skip"`).
- Button labels ("Good", "Bad", "Skip") and empty-state text ("You're all caught up!") stay unchanged — `spec/system/feedback_flow_spec.rb` and `spec/requests/feedback_spec.rb` assert on this exact text.
- Keep the existing `feedback-card`, `feedback-card--empty`, and `feedback-card__actions` class names in place alongside the new Tailwind utilities — do not remove them.
- No new CSS files, no new specs — reuse the two existing spec files as the verification step.

---

### Task 1: Restyle the feedback page heading, card, and empty state

**Files:**
- Modify: `app/views/feedback/index.html.erb`
- Modify: `app/views/feedback/_card.html.erb`
- Test (run, not modified): `spec/requests/feedback_spec.rb`
- Test (run, not modified): `spec/system/feedback_flow_spec.rb`

**Interfaces:**
- Consumes: `@event` (a `RecommendationEvent` or `nil`) passed from `FeedbackController#index` into the `feedback/card` partial — already the current contract, unchanged.
- Produces: nothing consumed by later tasks — this plan has only one task.

- [ ] **Step 1: Confirm the baseline specs pass before making any changes**

Run:
```bash
bin/rspec spec/requests/feedback_spec.rb spec/system/feedback_flow_spec.rb
```
Expected: all examples pass (this is the pre-change baseline; if anything is already red, stop and investigate before restyling).

- [ ] **Step 2: Add the page heading to `app/views/feedback/index.html.erb`**

Replace the full contents of `app/views/feedback/index.html.erb` (currently just the turbo-frame) with:

```erb
<h1 class="text-2xl font-bold mb-4">Feedback</h1>

<turbo-frame id="feedback_card">
  <%= render "feedback/card", event: @event %>
</turbo-frame>
```

- [ ] **Step 3: Restyle the card partial in `app/views/feedback/_card.html.erb`**

Replace the full contents of `app/views/feedback/_card.html.erb` with:

```erb
<% if event.nil? %>
  <div class="feedback-card feedback-card--empty max-w-xl p-6 border border-gray-200 rounded-lg bg-gray-50 text-center text-gray-500">
    You're all caught up!
  </div>
<% else %>
  <div class="feedback-card max-w-xl p-4 border border-gray-200 rounded-lg bg-gray-50" data-controller="feedback" data-feedback-event-id-value="<%= event.id %>">
    <h2 class="text-lg font-semibold"><%= event.album.title %></h2>
    <p class="text-gray-600"><%= event.album.artists.join(", ") %></p>
    <p class="mt-2 text-gray-800"><%= event.explanation %></p>

    <div class="feedback-card__actions mt-4 flex gap-3">
      <button type="button" data-action="feedback#choose" data-feedback-outcome-param="good" class="rounded-md px-3.5 py-2.5 bg-green-600 hover:bg-green-500 text-white font-medium cursor-pointer">Good</button>
      <button type="button" data-action="feedback#choose" data-feedback-outcome-param="bad" class="rounded-md px-3.5 py-2.5 bg-red-600 hover:bg-red-500 text-white font-medium cursor-pointer">Bad</button>
      <button type="button" data-action="feedback#choose" data-feedback-outcome-param="skip" class="rounded-md px-3.5 py-2.5 bg-gray-100 hover:bg-gray-200 text-gray-700 font-medium cursor-pointer">Skip</button>
    </div>
  </div>
<% end %>
```

- [ ] **Step 4: Run the existing specs to confirm nothing broke**

Run:
```bash
bin/rspec spec/requests/feedback_spec.rb spec/system/feedback_flow_spec.rb
```
Expected: all examples pass, unmodified — same count as the Step 1 baseline. `spec/requests/feedback_spec.rb` still finds the album title text and the `data-feedback-event-id-value="..."` attribute in the response body; `spec/system/feedback_flow_spec.rb` still finds the album title, clicks "Good" by its exact label, and sees "You're all caught up!" afterward.

- [ ] **Step 5: Visually verify in the browser**

Start the dev server (`bin/dev` or `rails server`, whichever this repo normally uses), sign in, and visit `/feedback` with at least one pending `RecommendationEvent` to confirm:
- The "Feedback" `<h1>` renders above the card, matching the Library/Vibe Map/Recommend pages.
- The card is bordered, rounded, and has the muted gray background — visually consistent with the Recommend page's result panel.
- The Good/Bad/Skip buttons render in green/red/gray with white/gray text as styled.
- After clicking a button, the empty state ("You're all caught up!") renders in the same bordered/rounded/muted style once no events remain pending.

- [ ] **Step 6: Commit**

```bash
git add app/views/feedback/index.html.erb app/views/feedback/_card.html.erb
git commit -m "Restyle feedback page with Tailwind card pattern"
```

---

## Self-Review

**Spec coverage:**
- Page heading (`h1` matching other pages) — Step 2. ✓
- Card restyle with border/rounded/muted background, `h2` title, secondary-gray body text — Step 3. ✓
- Empty state restyle, same bordered/rounded/muted treatment — Step 3. ✓
- All `data-*` attributes and button labels preserved byte-for-byte — Step 3 (verbatim from spec). ✓
- Existing `feedback-card`/`feedback-card--empty`/`feedback-card__actions` classes kept — Step 3 (verbatim from spec). ✓
- No route/controller/model/Stimulus/Turbo Stream changes — Global Constraints, no such files touched. ✓
- Existing specs (`spec/requests/feedback_spec.rb`, `spec/system/feedback_flow_spec.rb`) verified passing before and after — Steps 1 and 4. ✓
- No new spec files — none added. ✓

**Placeholder scan:** No TBD/TODO/"add appropriate" language; all code steps show complete file contents.

**Type consistency:** N/A — no new methods, functions, or cross-task interfaces beyond the single task's ERB templates.
