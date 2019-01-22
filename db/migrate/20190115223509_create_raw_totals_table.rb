class CreateRawTotalsTable < ActiveRecord::Migration[5.2]
  def up
    create_table :raw_size_totals do |t|
      
      t.integer :size_count
      t.string :size_name
      t.string :size_value
      
     
      
    end
    
    
  end

  def down
    
    drop_table :raw_size_totals
    
    
  end
  
end
