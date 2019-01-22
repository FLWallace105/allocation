class CreateAllocationSizeTypesTable < ActiveRecord::Migration[5.2]
  def up
    create_table :allocation_size_types do |t|
      t.string :collection_name
      t.integer :collection_id
      t.string :collection_size_type

    end

  end

  def down
    drop_table :allocation_size_types

  end
end
