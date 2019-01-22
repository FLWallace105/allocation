class CreateAllocationAlternateProductsTable < ActiveRecord::Migration[5.2]
  def up
    create_table :allocation_alternate_products do |t|
      t.string :product_title
      t.string :product_id
      t.string :variant_id
      t.string :sku
      t.string :product_collection
    
    end

  end
  def down
    drop_table :allocation_alternate_products
  end
end
