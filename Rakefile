require 'redis'
require 'resque'
Resque.redis = Redis.new(url: ENV['REDIS_URL'])
require 'active_record'
#require 'sinatra'
require 'sinatra/activerecord/rake'
require 'resque/tasks'
require_relative 'allocation'

#require 'pry'

namespace :allocate do
desc 'figure out total size counts per item ex tops XL = 523'
task :figure_size_counts do |t|
    Allocation::Setup.new.figure_size_counts
end

desc 'get the real size counts for active subs'
task :get_real_size_counts do |t|
    Allocation::Setup.new.get_real_size_counts
end

desc 'setup the subscriptions_next_month_updated table'
task :setup_next_month_subs_table do |t|
    Allocation::Setup.new.setup_subscriptions_to_be_updated
end

desc 'allocate subscriptions'
task :allocate_subscriptions_next_month do |t|
    Allocation::Setup.new.allocate_subscriptions
end

desc 'load the allocation_collections file into the table'
task :load_allocate_collections do |t|
    Allocation::Setup.new.load_allocation_collections
end


desc 'load the allocation_size_types table from CSV'
task :load_allocation_size_types do |t|
    Allocation::Setup.new.load_allocation_size_types

end


desc 'load allocation_inventory table from CSV'
task :load_allocation_inventory do |t|
    Allocation::Setup.new.load_allocation_inventory
end

desc 'background allocate subscriptions'
task :background_allocate_subs do |t|
    Allocation::Setup.new.background_allocate_subscriptions
end


desc 'load allocation_switchable_products table from CSV'
task :load_allocation_switchable_products do |t|
    Allocation::Setup.new.load_allocation_switchable_products_table
end


desc 'load allocation_matching_products table from CSV'
task :load_allocation_matching_products do |t|
    Allocation::Setup.new.load_allocation_matching_products
end

desc 'load allocation_alternate_products table from CSV'
task :load_allocation_alternate_products do |t|
    Allocation::Setup.new.load_allocation_alternate_products
end

desc 'load orders_next_month_updated table via SQL statements'
task :load_orders_next_month_updated do |t|
    Allocation::Setup.new.setup_orders_to_be_updated
end


desc 'background prepaid orders to be updated'
task :background_prepaid_orders do |t|
    Allocation::Setup.new.background_allocate_orders
end


end