class CreateAllocationCollectionTable < ActiveRecord::Migration[5.2]
  def up
    create_table :allocation_collections do |t|
      t.string :collection_name
      t.integer :collection_id
      t.string :collection_product_id

    end

  end
  def down
    drop_table :allocation_collections
  end
end
