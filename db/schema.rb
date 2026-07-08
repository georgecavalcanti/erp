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

ActiveRecord::Schema[8.1].define(version: 2026_07_07_233002) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "companies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "external_code", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["external_code"], name: "index_companies_on_external_code", unique: true
  end

  create_table "delinquencies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "import_batch_id"
    t.decimal "open_total", precision: 15, scale: 2, default: "0.0", null: false
    t.decimal "protested_2024", precision: 15, scale: 2, default: "0.0", null: false
    t.decimal "protested_2025", precision: 15, scale: 2, default: "0.0", null: false
    t.decimal "protested_2026", precision: 15, scale: 2, default: "0.0", null: false
    t.decimal "saldo_reported", precision: 15, scale: 2
    t.bigint "salesperson_id"
    t.string "salesperson_label", null: false
    t.datetime "updated_at", null: false
    t.index ["import_batch_id"], name: "index_delinquencies_on_import_batch_id"
    t.index ["salesperson_id"], name: "index_delinquencies_on_salesperson_id"
    t.index ["salesperson_label"], name: "index_delinquencies_on_salesperson_label"
  end

  create_table "import_batches", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_message"
    t.integer "kind", default: 0, null: false
    t.string "original_filename", null: false
    t.date "period_end"
    t.date "period_start"
    t.date "reference_date"
    t.integer "rows_imported", default: 0, null: false
    t.integer "rows_skipped", default: 0, null: false
    t.integer "rows_total", default: 0, null: false
    t.integer "rows_updated", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["user_id"], name: "index_import_batches_on_user_id"
  end

  create_table "invoices", force: :cascade do |t|
    t.decimal "commission", precision: 15, scale: 2, default: "0.0", null: false
    t.bigint "company_id"
    t.boolean "confirmed", default: true, null: false
    t.datetime "created_at", null: false
    t.date "due_date"
    t.bigint "external_uid", null: false
    t.date "first_due_date"
    t.bigint "import_batch_id"
    t.jsonb "installment_offsets", default: [], null: false
    t.integer "invoice_number"
    t.integer "kind", default: 0, null: false
    t.string "nature_desc"
    t.date "negotiation_date", null: false
    t.string "nfe_status"
    t.string "nfse_status"
    t.string "operation_type_desc"
    t.integer "order_number"
    t.boolean "paid", default: false, null: false
    t.datetime "paid_at"
    t.bigint "partner_id"
    t.string "payment_terms_raw"
    t.jsonb "raw", default: {}, null: false
    t.string "result_center_desc"
    t.bigint "salesperson_id"
    t.decimal "total_value", precision: 15, scale: 2, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "negotiation_date"], name: "index_invoices_on_company_id_and_negotiation_date"
    t.index ["company_id"], name: "index_invoices_on_company_id"
    t.index ["external_uid"], name: "index_invoices_on_external_uid", unique: true
    t.index ["import_batch_id"], name: "index_invoices_on_import_batch_id"
    t.index ["kind"], name: "index_invoices_on_kind"
    t.index ["negotiation_date", "kind"], name: "index_invoices_on_negotiation_date_and_kind"
    t.index ["negotiation_date"], name: "index_invoices_on_negotiation_date"
    t.index ["paid", "due_date"], name: "index_invoices_on_paid_and_due_date"
    t.index ["partner_id", "negotiation_date"], name: "index_invoices_on_partner_id_and_negotiation_date"
    t.index ["partner_id"], name: "index_invoices_on_partner_id"
    t.index ["salesperson_id", "negotiation_date"], name: "index_invoices_on_salesperson_id_and_negotiation_date"
    t.index ["salesperson_id"], name: "index_invoices_on_salesperson_id"
  end

  create_table "overdue_titles", force: :cascade do |t|
    t.decimal "amount", precision: 15, scale: 2, default: "0.0", null: false
    t.integer "category", default: 0, null: false
    t.datetime "created_at", null: false
    t.date "due_date"
    t.bigint "import_batch_id"
    t.integer "invoice_number"
    t.text "observation"
    t.bigint "partner_id"
    t.string "partner_name"
    t.integer "protest_year"
    t.bigint "salesperson_id"
    t.string "salesperson_label", null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_overdue_titles_on_category"
    t.index ["due_date"], name: "index_overdue_titles_on_due_date"
    t.index ["import_batch_id"], name: "index_overdue_titles_on_import_batch_id"
    t.index ["partner_id"], name: "index_overdue_titles_on_partner_id"
    t.index ["salesperson_id"], name: "index_overdue_titles_on_salesperson_id"
    t.index ["salesperson_label"], name: "index_overdue_titles_on_salesperson_label"
  end

  create_table "partners", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "external_code", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["external_code"], name: "index_partners_on_external_code", unique: true
    t.index ["name"], name: "index_partners_on_name"
  end

  create_table "pending_orders", force: :cascade do |t|
    t.decimal "commission", precision: 15, scale: 2, default: "0.0", null: false
    t.bigint "company_id"
    t.datetime "created_at", null: false
    t.string "delivery_type"
    t.bigint "external_uid", null: false
    t.bigint "import_batch_id"
    t.date "movement_date"
    t.date "negotiation_date"
    t.string "note_status"
    t.string "operation_type_desc"
    t.integer "order_number"
    t.bigint "partner_id"
    t.string "partner_name"
    t.boolean "pending", default: true, null: false
    t.boolean "printed", default: false, null: false
    t.jsonb "raw", default: {}, null: false
    t.bigint "salesperson_id"
    t.string "salesperson_label"
    t.decimal "total_value", precision: 15, scale: 2, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_pending_orders_on_company_id"
    t.index ["external_uid"], name: "index_pending_orders_on_external_uid"
    t.index ["import_batch_id"], name: "index_pending_orders_on_import_batch_id"
    t.index ["negotiation_date"], name: "index_pending_orders_on_negotiation_date"
    t.index ["partner_id"], name: "index_pending_orders_on_partner_id"
    t.index ["salesperson_id", "negotiation_date"], name: "index_pending_orders_on_salesperson_id_and_negotiation_date"
    t.index ["salesperson_id"], name: "index_pending_orders_on_salesperson_id"
  end

  create_table "salespeople", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "external_code", null: false
    t.string "nickname", null: false
    t.datetime "updated_at", null: false
    t.index ["external_code"], name: "index_salespeople_on_external_code", unique: true
    t.index ["nickname"], name: "index_salespeople_on_nickname"
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

  add_foreign_key "delinquencies", "import_batches"
  add_foreign_key "delinquencies", "salespeople"
  add_foreign_key "import_batches", "users"
  add_foreign_key "invoices", "companies"
  add_foreign_key "invoices", "import_batches"
  add_foreign_key "invoices", "partners"
  add_foreign_key "invoices", "salespeople"
  add_foreign_key "overdue_titles", "import_batches"
  add_foreign_key "overdue_titles", "partners"
  add_foreign_key "overdue_titles", "salespeople"
  add_foreign_key "pending_orders", "companies"
  add_foreign_key "pending_orders", "import_batches"
  add_foreign_key "pending_orders", "partners"
  add_foreign_key "pending_orders", "salespeople"
  add_foreign_key "sessions", "users"
end
