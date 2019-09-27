class ModifyAllocationSwitchableProducts < ActiveRecord::Migration[5.2]
  def up 
    remove_column :allocation_switchable_products, :threepk, :boolean
    add_column :allocation_switchable_products, :prod_type, :integer
    
  end

  def down
    add_column :allocation_switchable_products, :threepk, :boolean
    remove_column :allocation_switchable_products, :prod_type, :integer

  end
end
