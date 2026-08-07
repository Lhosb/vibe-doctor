# README

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...

## Local mood_probe development

The app resolves `mood_probe` from GitHub for reproducible builds. To use the
adjacent local checkout during development:

```sh
bundle config set --local local.mood_probe ~/projects/gems/mood_probe
bundle install
```

The local checkout must be on the `main` branch named in the Gemfile.

Phase 3 intentionally keeps one `MoodProbe::Extractor#analyze` call per track.
The gem's current `analyze_all` implementation is itself a loop, so switching
would not reduce process spawns and would keep every downloaded preview alive
until the whole album completed. Phase 3.5 will switch when batching provides
an actual runtime benefit.
