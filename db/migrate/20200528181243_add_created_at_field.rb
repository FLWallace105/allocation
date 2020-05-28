class AddCreatedAtField < ActiveRecord::Migration[5.2]
  def up 
    add_column :subscriptions_next_month_updated, :created_at, :datetime
    
  end

  def down
    
    remove_column :subscriptions_next_month_updated, :created_at, :datetime

  end
end
