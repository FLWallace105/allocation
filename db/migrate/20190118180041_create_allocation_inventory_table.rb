class CreateAllocationInventoryTable < ActiveRecord::Migration[5.2]
  def up
    create_table :allocation_inventory do |t|
      t.string :collection_name
      t.integer :collection_id
      t.integer :inventory_available
      t.integer :inventory_reserved
      t.string :size
      t.string :mytype


    end
  end

  def down
    drop_table :allocation_inventory

  end
end
