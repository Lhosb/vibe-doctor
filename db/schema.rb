# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_22_170000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vector"

  create_table "album_affinities", force: :cascade do |t|
    t.bigint "album_id", null: false
    t.datetime "created_at", null: false
    t.datetime "last_interacted_at"
    t.float "score", default: 0.0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["album_id"], name: "index_album_affinities_on_album_id"
    t.index ["user_id", "album_id"], name: "index_album_affinities_on_user_id_and_album_id", unique: true
    t.index ["user_id"], name: "index_album_affinities_on_user_id"
  end

  create_table "albums", force: :cascade do |t|
    t.string "artists", default: [], null: false, array: true
    t.datetime "created_at", null: false
    t.string "enrichment_status", default: "pending", null: false
    t.string "genres", default: [], null: false, array: true
    t.bigint "master_id", null: false
    t.string "styles", default: [], null: false, array: true
    t.boolean "synthetic_master_id", default: false, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "year"
    t.string "youtube_url"
    t.index ["master_id"], name: "index_albums_on_master_id", unique: true
  end

  create_table "artist_cooldowns", force: :cascade do |t|
    t.string "artist_name", null: false
    t.datetime "created_at", null: false
    t.datetime "last_recommended_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "artist_name"], name: "index_artist_cooldowns_on_user_id_and_artist_name", unique: true
    t.index ["user_id"], name: "index_artist_cooldowns_on_user_id"
  end

  create_table "collection_items", force: :cascade do |t|
    t.bigint "album_id", null: false
    t.datetime "created_at", null: false
    t.bigint "release_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["album_id"], name: "index_collection_items_on_album_id"
    t.index ["user_id", "release_id"], name: "index_collection_items_on_user_id_and_release_id", unique: true
    t.index ["user_id"], name: "index_collection_items_on_user_id"
  end

  create_table "embeddings", force: :cascade do |t|
    t.bigint "album_id", null: false
    t.datetime "created_at", null: false
    t.vector "emotional", limit: 1536
    t.vector "era", limit: 1536
    t.vector "situational", limit: 1536
    t.vector "sonic", limit: 1536
    t.datetime "updated_at", null: false
    t.index ["album_id"], name: "index_embeddings_on_album_id", unique: true
  end

  create_table "mood_vectors", force: :cascade do |t|
    t.bigint "album_id", null: false
    t.float "arousal", default: 0.5, null: false
    t.datetime "created_at", null: false
    t.float "danceability", default: 0.5, null: false
    t.float "match_confidence", default: 0.0, null: false
    t.float "mood_acoustic", default: 0.5, null: false
    t.float "mood_happy", default: 0.5, null: false
    t.float "mood_relaxed", default: 0.5, null: false
    t.string "mood_source", default: "llm_only", null: false
    t.jsonb "spread", default: {}, null: false
    t.datetime "updated_at", null: false
    t.float "valence", default: 0.5, null: false
    t.index ["album_id"], name: "index_mood_vectors_on_album_id", unique: true
    t.check_constraint "mood_source::text = ANY (ARRAY['essentia_itunes'::character varying::text, 'essentia_youtube'::character varying::text, 'llm_only'::character varying::text])", name: "mood_vectors_mood_source_check"
  end

  create_table "query_understanding_caches", force: :cascade do |t|
    t.float "arousal", null: false
    t.datetime "created_at", null: false
    t.float "danceability", null: false
    t.vector "embedding", limit: 1536, null: false
    t.datetime "expires_at", null: false
    t.string "genre"
    t.jsonb "keywords", default: [], null: false
    t.float "mood_acoustic", null: false
    t.float "mood_happy", null: false
    t.float "mood_relaxed", null: false
    t.string "query_digest", null: false
    t.text "query_text", null: false
    t.datetime "updated_at", null: false
    t.float "valence", null: false
    t.index ["query_digest"], name: "index_query_understanding_caches_on_query_digest", unique: true
  end

  create_table "recommendation_events", force: :cascade do |t|
    t.bigint "album_id", null: false
    t.jsonb "blended_scores", default: {}, null: false
    t.integer "candidates_considered", null: false
    t.datetime "created_at", null: false
    t.text "explanation"
    t.float "final_score", null: false
    t.string "outcome", default: "pending", null: false
    t.text "query_text", null: false
    t.jsonb "rerank_scores", default: {}, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["album_id"], name: "index_recommendation_events_on_album_id"
    t.index ["outcome"], name: "index_recommendation_events_on_outcome"
    t.index ["user_id"], name: "index_recommendation_events_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.string "discogs_token"
    t.string "discogs_username"
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  create_table "vibe_cards", force: :cascade do |t|
    t.string "activities", default: [], null: false, array: true
    t.bigint "album_id", null: false
    t.datetime "created_at", null: false
    t.string "energy_arc", default: "", null: false
    t.text "prose", default: "", null: false
    t.string "seasons", default: [], null: false, array: true
    t.string "texture", default: "", null: false
    t.string "time_of_day", default: [], null: false, array: true
    t.datetime "updated_at", null: false
    t.index ["album_id"], name: "index_vibe_cards_on_album_id", unique: true
  end

  create_table "vibe_overrides", force: :cascade do |t|
    t.bigint "album_id", null: false
    t.float "arousal"
    t.datetime "created_at", null: false
    t.float "danceability"
    t.string "genre"
    t.float "mood_acoustic"
    t.float "mood_happy"
    t.float "mood_relaxed"
    t.string "source"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.float "valence"
    t.index ["album_id"], name: "index_vibe_overrides_on_album_id"
    t.index ["user_id", "album_id"], name: "index_vibe_overrides_on_user_id_and_album_id", unique: true
    t.index ["user_id"], name: "index_vibe_overrides_on_user_id"
  end

  add_foreign_key "album_affinities", "albums"
  add_foreign_key "album_affinities", "users"
  add_foreign_key "artist_cooldowns", "users"
  add_foreign_key "collection_items", "albums"
  add_foreign_key "collection_items", "users"
  add_foreign_key "embeddings", "albums"
  add_foreign_key "mood_vectors", "albums"
  add_foreign_key "recommendation_events", "albums"
  add_foreign_key "recommendation_events", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "vibe_cards", "albums"
  add_foreign_key "vibe_overrides", "albums"
  add_foreign_key "vibe_overrides", "users"
end
