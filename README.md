# Vibe Doctor

Vibe Doctor is a Rails app for mood-based music discovery. It syncs a user's
Discogs collection, enriches albums with audio and LLM-generated metadata, and
recommends records that fit a free-form listening prompt.

## Features

- Sync a personal record collection from Discogs
- Enrich albums in the background with mood vectors, vibe cards, and embeddings
- Browse the collection and inspect per-album mood details
- Explore a two-axis vibe map of the collection
- Request recommendations from natural-language prompts, with optional genre input
- Capture recommendation feedback to improve future ranking
- Generate per-user API tokens for headless clients such as iOS Shortcuts
- Manage users, invitations, and data from the built-in admin area

## Tech stack

- Ruby 4.0.1
- Rails 8.1
- PostgreSQL
- Hotwire (Turbo + Stimulus) with Import Maps
- Tailwind CSS
- Solid Queue / Solid Cache / Solid Cable in production
- RSpec, Capybara, FactoryBot, and WebMock
- Kamal for containerized deployment

## How it works

1. A user connects their Discogs account and syncs their collection.
2. New albums are queued for enrichment.
3. The enrichment pipeline derives mood features from audio, generates a
   descriptive vibe card, and stores embeddings for retrieval.
4. A recommendation request is translated into structured intent, matched
   against the user's collection, reranked, and returned with an explanation.
5. User feedback updates album affinity signals for future recommendations.

## Prerequisites

Install the following before starting local development:

- Ruby 4.0.1
- Bundler
- PostgreSQL
- `libpq` development headers for the `pg` gem

If you want to run the full audio enrichment flow locally, also install:

- Python 3
- `ffmpeg`

## Configuration

The app uses `.env` in development.

Create a `.env` file for the flows you plan to use. Common development values:

```sh
ADMIN_EMAIL=you@example.com
SEED_USER_PASSWORD=changeme123
OPENAI_API_KEY=your_openai_api_key
```

Optional variables used by enrichment and deployment-related flows include:

- `ESSENTIA_MODELS_DIR`
- `GROUNDING_TRACKS_PER_ALBUM`
- `YOUTUBE_MATCH_CONFIDENCE_THRESHOLD`
- `ENABLE_YOUTUBE_GROUNDING`

`ADMIN_EMAIL` and `SEED_USER_PASSWORD` are only needed if you want to seed a local
admin account. `OPENAI_API_KEY` is required for recommendation and enrichment
features that call OpenAI.

Discogs credentials are entered per user in the app and are not required to boot
the project.

## Setup

Install dependencies and prepare the database:

```sh
bin/setup --skip-server
```

If you want a seeded admin user for local development, run:

```sh
bin/rails db:seed
```

## Running the app

Start the development server:

```sh
bin/dev
```

This starts Rails and the Tailwind watcher. The app is available at
http://localhost:3000.

## Development workflow

- Sign in with the seeded admin user, or create invite links from the admin area
- Connect Discogs from the **Discogs Settings** page to import a collection
- Open **Library** to confirm albums were synced
- Use **Recommend** to request a mood-based recommendation
- Use **Feedback** to mark recommendations as good, bad, or skipped
- Use **API Access** to generate a token for Shortcut or other headless clients

## Testing and quality checks

Run the main checks used by CI:

```sh
bin/rubocop
bin/brakeman --no-pager
bin/bundler-audit
bin/importmap audit
bin/rails assets:precompile
bin/rails db:test:prepare
bundle exec rspec
```

The test suite uses PostgreSQL.

### Essentia golden specs

The repository also has an Essentia-specific integration test path that runs in
the amd64 app image:

```sh
docker build --platform linux/amd64 -t vibe-doctor-essentia-goldens .
docker run --rm --platform linux/amd64 --entrypoint bash \
  -e ESSENTIA_SPECS=1 -e RAILS_ENV=test \
  vibe-doctor-essentia-goldens \
  -c 'bundle exec rspec spec/integration/essentia_extract_golden_spec.rb'
```

## Deployment

Production deployment is set up for Kamal.

- Main deployment config: `config/deploy.yml`
- Container build: `Dockerfile`
- Production uses PostgreSQL plus Solid Queue, Solid Cache, and Solid Cable
- Required production secrets are injected through Kamal secrets and environment
  variables

## Local `sonance` development

The app resolves `sonance` from GitHub for reproducible builds. To use an
adjacent local checkout during development:

```sh
bundle config set --local local.sonance ~/projects/gems/sonance
bundle install
```

The local checkout must be on the `main` branch named in the Gemfile.

Phase 3 intentionally keeps one `Sonance::Extractor#analyze` call per track.
The gem's current `analyze_all` implementation is itself a loop, so switching
would not reduce process spawns and would keep every downloaded preview alive
until the whole album completed. Phase 3.5 will switch when batching provides
an actual runtime benefit.

## Licences

This application is MIT-licensed. See [LICENSE](LICENSE).

The Essentia model files used by this application are CC BY-NC-ND 4.0 and are
fetched at image build time from essentia.upf.edu. Essentia itself is AGPL-3.0.
See [NOTICE](NOTICE) for full attribution, licence URIs, and per-model source
URLs.
