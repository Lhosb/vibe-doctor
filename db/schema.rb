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

ActiveRecord::Schema[8.1].define(version: 2026_07_21_214351) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vector"

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
    t.index ["master_id"], name: "index_albums_on_master_id", unique: true
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

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
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

  add_foreign_key "embeddings", "albums"
  add_foreign_key "mood_vectors", "albums"
  add_foreign_key "sessions", "users"
  add_foreign_key "vibe_cards", "albums"
end
