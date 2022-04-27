#model.rb

class Subscription < ActiveRecord::Base
    self.table_name = "subscriptions"
end

class SubCollectionSize < ActiveRecord::Base
    self.table_name = "sub_collection_sizes"

end

class Order < ActiveRecord::Base
    self.table_name = "orders"
end

class OrderCollectionSize < ActiveRecord::Base
    self.table_name = "order_collection_sizes"
end

class SubscriptionLineItem < ActiveRecord::Base
    self.table_name = "sub_line_items"
end

class RawSizeTotal < ActiveRecord::Base
    self.table_name = "raw_size_totals"
end

class SubscriptionsNextMonthUpdate < ActiveRecord::Base
    self.table_name = "subscriptions_next_month_updated"
end

class SubLineItem < ActiveRecord::Base
    self.table_name = "sub_line_items"
end

class AllocationCollection < ActiveRecord::Base
    self.table_name ="allocation_collections"
end

class AllocationSizeType < ActiveRecord::Base
    self.table_name = "allocation_size_types"
end

class AllocationInventory < ActiveRecord::Base
    self.table_name = "allocation_inventory"
end

class SubNextMonthDryRun < ActiveRecord::Base
    self.table_name = "subs_next_month_dry_run"
end

class AllocationSwitchableProduct < ActiveRecord::Base
    self.table_name = "allocation_switchable_products"
    #prepaid method here
    def prepaid?
        self.prepaid

    end
end

class AllocationMatchingProduct < ActiveRecord::Base
    self.table_name = "allocation_matching_products"
end


class AllocationAlternateProduct < ActiveRecord::Base
    self.table_name = "allocation_alternate_products"
end


class OrdersNextMonthUpdate < ActiveRecord::Base
    self.table_name = "orders_next_month_updated"
end