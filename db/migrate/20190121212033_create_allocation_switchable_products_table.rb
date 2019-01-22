class CreateAllocationSwitchableProductsTable < ActiveRecord::Migration[5.2]
  def up
    create_table :allocation_switchable_products do |t|
      t.string :product_title
      t.string :shopify_product_id
      t.boolean :threepk, default: false
      t.boolean :prepaid, default:false


    end

  end

  def down
    drop_table :allocation_switchable_products

  end


end
