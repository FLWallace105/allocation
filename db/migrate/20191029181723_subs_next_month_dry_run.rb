class SubsNextMonthDryRun < ActiveRecord::Migration[5.2]
  def up

    create_table :subs_next_month_dry_run do |t|

      

      t.string :subscription_id
      t.string :customer_id
      t.datetime :updated_at
      t.datetime :next_charge_scheduled_at
      t.string :product_title
      t.string :status
      t.string :sku
      t.string :shopify_product_id
      t.string :shopify_variant_id
      t.jsonb :raw_line_items
      t.boolean :updated, default: false
      t.boolean :bad_subscription, default: false
      t.datetime :processed_at


      

    end
    #add_index :orders_next_month_updated, :order_id
    



  end

  def down

    drop_table :subs_next_month_dry_run
  end
end
