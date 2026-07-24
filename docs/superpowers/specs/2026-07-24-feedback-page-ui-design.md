# Feedback page UI makeover — design

## Context

The `/feedback` page (`FeedbackController#index`, `app/views/feedback/index.html.erb`) shows one pending `RecommendationEvent` at a time inside a `<turbo-frame id="feedback_card">`, rendered by `app/views/feedback/_card.html.erb`. The listener rates it Good/Bad/Skip; the `feedback` Stimulus controller (`app/javascript/controllers/feedback_controller.js`) POSTs to `/feedback` and swaps in the next card via a Turbo Stream response (`app/views/feedback/create.turbo_stream.erb`), or shows an empty state once nothing is pending.

Right now the card is unstyled: no Tailwind classes, no custom CSS anywhere in `app/assets/stylesheets/`, no page heading. Every other page in the app (Library, Vibe Map, Recommend) opens with `<h1 class="text-2xl font-bold mb-4">...</h1>` and uses Tailwind utility classes throughout. The Recommend page's result panel (`app/javascript/controllers/recommend_controller.js#renderResult`) recently established a card pattern for showing one album's info — bordered, rounded, muted background, `h2` title, secondary-gray body text — that this makeover reuses so the two "single album card" surfaces in the app look related.

This is a **pure visual restyle**. No route, controller, model, Stimulus behavior, or Turbo wiring changes.

## Design

**`app/views/feedback/index.html.erb`** — add a page heading matching every other page:

```erb
<h1 class="text-2xl font-bold mb-4">Feedback</h1>

<turbo-frame id="feedback_card">
  <%= render "feedback/card", event: @event %>
</turbo-frame>
```

**`app/views/feedback/_card.html.erb`** — restyle the card and empty state; all `data-*` attributes, the turbo-frame's Stimulus wiring, and the button labels stay byte-for-byte identical to today:

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

Notes:
- The existing `feedback-card`, `feedback-card--empty`, and `feedback-card__actions` class names are kept alongside the new Tailwind utilities — they carry no CSS today (grep of `app/assets/stylesheets/` confirms no rules reference them) but removing them isn't necessary for this change and keeps the diff focused on additive styling.
- Button labels ("Good", "Bad", "Skip") and the empty-state text ("You're all caught up!") are unchanged, since `spec/system/feedback_flow_spec.rb` (`click_button "Good"`, `have_content("You're all caught up!")`) and `spec/requests/feedback_spec.rb` (`include(event.album.title)`, `include(%(data-feedback-event-id-value="..."))`, `include("You're all caught up!")`) assert on this exact text.
- No album art/cover image exists in this app's data model (`Album` has no image/cover field), so the card is text-only, consistent with the rest of the app.

## Testing

No behavior changed, so no new specs are required. The existing coverage must keep passing unmodified:
- `spec/requests/feedback_spec.rb` — asserts on album title text and the `data-feedback-event-id-value` attribute being present in the response body; both survive the restyle since neither the text content nor that attribute's name/value changes.
- `spec/system/feedback_flow_spec.rb` — visits `/feedback`, asserts album title content, clicks the "Good" button by its exact label, and asserts the empty-state text after advancing; all three continue to work since the button labels, click targets, and empty-state copy are unchanged.

The implementation task should run both specs after the restyle to confirm nothing broke, but no new spec files are needed.

## Out of scope

- Any change to `FeedbackController`, `RecommendationEvent`, the Turbo Stream response, or the `feedback` Stimulus controller's logic.
- Adding album art/cover images (no such data exists in this app).
- A "history" view of past feedback, or any new feedback-related route.
- Removing the pre-existing `feedback-card`/`feedback-card--empty`/`feedback-card__actions` class names — left in place since they're harmless and out of scope for a styling-only change.
