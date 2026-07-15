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

ActiveRecord::Schema[8.1].define(version: 2026_07_15_170001) do
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

  create_table "invoice_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "discount_value", precision: 15, scale: 2, default: "0.0", null: false
    t.integer "external_sequence", null: false
    t.decimal "gross_value", precision: 15, scale: 2, default: "0.0", null: false
    t.bigint "invoice_id", null: false
    t.decimal "margin_value", precision: 15, scale: 2
    t.decimal "net_value", precision: 15, scale: 2, default: "0.0", null: false
    t.bigint "product_id"
    t.decimal "quantity", precision: 15, scale: 4, default: "0.0", null: false
    t.jsonb "raw", default: {}, null: false
    t.decimal "total_cost", precision: 15, scale: 2
    t.decimal "unit_cost", precision: 15, scale: 6
    t.decimal "unit_price", precision: 15, scale: 6
    t.datetime "updated_at", null: false
    t.index ["invoice_id", "external_sequence"], name: "index_invoice_items_on_invoice_id_and_external_sequence", unique: true
    t.index ["invoice_id"], name: "index_invoice_items_on_invoice_id"
    t.index ["product_id"], name: "index_invoice_items_on_product_id"
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
    t.datetime "items_synced_at"
    t.integer "kind", default: 0, null: false
    t.decimal "margin_percent", precision: 7, scale: 4
    t.decimal "margin_value", precision: 15, scale: 2
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
    t.decimal "total_cost", precision: 15, scale: 2
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

  create_table "order_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "discount_value", precision: 15, scale: 2, default: "0.0", null: false
    t.integer "external_sequence", null: false
    t.decimal "gross_value", precision: 15, scale: 2, default: "0.0", null: false
    t.decimal "margin_value", precision: 15, scale: 2
    t.decimal "net_value", precision: 15, scale: 2, default: "0.0", null: false
    t.bigint "order_id", null: false
    t.bigint "product_id"
    t.decimal "quantity", precision: 15, scale: 4, default: "0.0", null: false
    t.jsonb "raw", default: {}, null: false
    t.decimal "total_cost", precision: 15, scale: 2
    t.decimal "unit_cost", precision: 15, scale: 6
    t.decimal "unit_price", precision: 15, scale: 6
    t.datetime "updated_at", null: false
    t.index ["order_id", "external_sequence"], name: "index_order_items_on_order_id_and_external_sequence", unique: true
    t.index ["order_id"], name: "index_order_items_on_order_id"
    t.index ["product_id"], name: "index_order_items_on_product_id"
  end

  create_table "orders", force: :cascade do |t|
    t.bigint "company_id"
    t.datetime "created_at", null: false
    t.string "delivery_type"
    t.bigint "external_uid", null: false
    t.datetime "items_synced_at"
    t.decimal "margin_percent", precision: 7, scale: 4
    t.decimal "margin_value", precision: 15, scale: 2
    t.date "movement_date"
    t.date "negotiation_date"
    t.string "note_status"
    t.integer "order_number"
    t.bigint "partner_id"
    t.string "partner_name"
    t.boolean "pending", default: true, null: false
    t.jsonb "raw", default: {}, null: false
    t.bigint "salesperson_id"
    t.string "salesperson_label"
    t.integer "status", default: 0, null: false
    t.decimal "total_cost", precision: 15, scale: 2
    t.decimal "total_value", precision: 15, scale: 2, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_orders_on_company_id"
    t.index ["external_uid"], name: "index_orders_on_external_uid", unique: true
    t.index ["partner_id"], name: "index_orders_on_partner_id"
    t.index ["salesperson_id", "status"], name: "index_orders_on_salesperson_id_and_status"
    t.index ["salesperson_id"], name: "index_orders_on_salesperson_id"
    t.index ["status"], name: "index_orders_on_status"
  end

  create_table "overdue_titles", force: :cascade do |t|
    t.decimal "amount", precision: 15, scale: 2, default: "0.0", null: false
    t.integer "category", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "days_overdue"
    t.date "due_date"
    t.bigint "external_uid"
    t.bigint "import_batch_id"
    t.integer "invoice_number"
    t.text "observation"
    t.bigint "partner_id"
    t.string "partner_name"
    t.integer "protest_year"
    t.bigint "salesperson_id"
    t.string "salesperson_label", null: false
    t.string "title_type"
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_overdue_titles_on_category"
    t.index ["due_date"], name: "index_overdue_titles_on_due_date"
    t.index ["external_uid"], name: "index_overdue_titles_on_external_uid"
    t.index ["import_batch_id"], name: "index_overdue_titles_on_import_batch_id"
    t.index ["partner_id"], name: "index_overdue_titles_on_partner_id"
    t.index ["salesperson_id"], name: "index_overdue_titles_on_salesperson_id"
    t.index ["salesperson_label"], name: "index_overdue_titles_on_salesperson_label"
  end

  create_table "partners", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "block_reason"
    t.boolean "blocked", default: false, null: false
    t.string "city"
    t.string "cnpj"
    t.datetime "created_at", null: false
    t.bigint "external_code", null: false
    t.date "last_negotiation_on"
    t.string "name", null: false
    t.jsonb "raw", default: {}, null: false
    t.string "segment"
    t.string "state"
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_partners_on_active"
    t.index ["cnpj"], name: "index_partners_on_cnpj"
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

  create_table "products", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "brand"
    t.bigint "category_external_code"
    t.string "category_name"
    t.datetime "created_at", null: false
    t.decimal "current_cost", precision: 15, scale: 5
    t.string "description", null: false
    t.bigint "external_code", null: false
    t.string "ncm"
    t.jsonb "raw", default: {}, null: false
    t.string "reference"
    t.string "unit"
    t.datetime "updated_at", null: false
    t.string "usage"
    t.index ["active"], name: "index_products_on_active"
    t.index ["category_external_code"], name: "index_products_on_category_external_code"
    t.index ["external_code"], name: "index_products_on_external_code", unique: true
  end

  create_table "salespeople", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "email"
    t.integer "external_code", null: false
    t.string "nickname", null: false
    t.jsonb "raw", default: {}, null: false
    t.string "seller_kind"
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_salespeople_on_active"
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

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "sync_runs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "error_messages", default: [], null: false
    t.datetime "finished_at", null: false
    t.string "status", null: false
    t.jsonb "summary", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["finished_at"], name: "index_sync_runs_on_finished_at"
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
  add_foreign_key "invoice_items", "invoices"
  add_foreign_key "invoice_items", "products"
  add_foreign_key "invoices", "companies"
  add_foreign_key "invoices", "import_batches"
  add_foreign_key "invoices", "partners"
  add_foreign_key "invoices", "salespeople"
  add_foreign_key "order_items", "orders"
  add_foreign_key "order_items", "products"
  add_foreign_key "orders", "companies"
  add_foreign_key "orders", "partners"
  add_foreign_key "orders", "salespeople"
  add_foreign_key "overdue_titles", "import_batches"
  add_foreign_key "overdue_titles", "partners"
  add_foreign_key "overdue_titles", "salespeople"
  add_foreign_key "pending_orders", "companies"
  add_foreign_key "pending_orders", "import_batches"
  add_foreign_key "pending_orders", "partners"
  add_foreign_key "pending_orders", "salespeople"
  add_foreign_key "sessions", "users"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
end
