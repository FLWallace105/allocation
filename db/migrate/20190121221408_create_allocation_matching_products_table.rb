class CreateAllocationMatchingProductsTable < ActiveRecord::Migration[5.2]
  def up
    create_table :allocation_matching_products do |t|
      t.string :product_title
      t.string :incoming_product_id
      t.boolean :threepk, default: false
      t.string :outgoing_product_id

    end

  end

  def down
    drop_table :allocation_matching_products


  end
end
