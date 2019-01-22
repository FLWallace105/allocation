#allocation.rb
require 'dotenv'
Dotenv.load
require 'httparty'
require 'resque'
require 'sinatra'
require 'active_record'
require "sinatra/activerecord"
require_relative 'models/model'
require_relative 'background_allocation_helper'
#require 'pry'

module Allocation
  class Setup
    
    def initialize
      Dotenv.load
      recharge_regular = ENV['RECHARGE_ACCESS_TOKEN']
      recharge_staging = ENV['STAGING_RECHARGE_ACCESS_TOKEN']
      
      @my_header = {
        "X-Recharge-Access-Token" => recharge_regular
      }
      @my_change_header = {
        "X-Recharge-Access-Token" => recharge_regular,
        "Accept" => "application/json",
        "Content-Type" =>"application/json"
      }
      @my_staging_header = {
        "X-Recharge-Access-Token" => recharge_staging
      }
      @my_staging_change_header = {
        "X-Recharge-Access-Token" => recharge_staging,
        "Accept" => "application/json",
        "Content-Type" =>"application/json"
      }

    end

    def figure_size_counts
        puts "Howdy figuring size counts"
        #Generate Initial Raw Size Totals

        RawSizeTotal.delete_all
        # Now reset index
        ActiveRecord::Base.connection.reset_pk_sequence!('raw_size_totals')

        size_count_sql = "insert into raw_size_totals (size_count, size_name, size_value) select count(subscriptions.id), sub_line_items.name, sub_line_items.value from subscriptions, sub_line_items where subscriptions.subscription_id = sub_line_items.subscription_id and subscriptions.status = 'ACTIVE' and (sub_line_items.name = 'leggings' or sub_line_items.name = 'sports-bra' or sub_line_items.name = 'tops' or sub_line_items.name = 'sports-jacket') group by sub_line_items.name, sub_line_items.value"

        ActiveRecord::Base.connection.execute(size_count_sql)


    end

    def accumulate_sizes(my_sizes, size_value, size_count)
        case size_value
        when "XS", "xs", "Xs", "xS"
            my_sizes["XS"] = my_sizes["XS"] + size_count
            
        when "S", "s"
            my_sizes["S"] = my_sizes["S"] + size_count
        
        when "M", "m"
            my_sizes["M"] = my_sizes["M"] + size_count
        
        when "L", "l"
            my_sizes["L"] = my_sizes["L"] + size_count
        
        when "XL", "xl", "Xl", "xL"
            my_sizes["XL"] = my_sizes["XL"] + size_count
        
        else 
            #figure its a blank, assign to XS
            my_sizes["XS"] = my_sizes['XS'] + size_count
        end

    end


    def figure_my_size(my_sizes, info, switch_value)
        #puts tops_sizes.inspect
        #puts "my info = #{info.inspect}"
        if switch_value == "tops" && info.size_name == "tops"
            accumulate_sizes(my_sizes, info.size_value, info.size_count)

        elsif switch_value == "leggings" && info.size_name == "leggings"
            accumulate_sizes(my_sizes, info.size_value, info.size_count)
            
        elsif switch_value == "sports-bra" && info.size_name == "sports-bra"
            accumulate_sizes(my_sizes, info.size_value, info.size_count)

        elsif switch_value == "sports-jacket" && info.size_name == "sports-jacket"
            accumulate_sizes(my_sizes, info.size_value, info.size_count)
            
        end

        
        
    end


    def get_real_size_counts
        puts "Getting real size counts"
        #start with tops
        tops_sizes = {"XS" => 0, "S" => 0, "M" => 0, "L" => 0, "XL" => 0}
        leggings_sizes = {"XS" => 0, "S" => 0, "M" => 0, "L" => 0, "XL" => 0}
        sports_bra_sizes = {"XS" => 0, "S" => 0, "M" => 0, "L" => 0, "XL" => 0}
        sports_jacket_sizes = {"XS" => 0, "S" => 0, "M" => 0, "L" => 0, "XL" => 0}

        my_raw_sizes = RawSizeTotal.all
        my_raw_sizes.each do |myraw|
            puts myraw.inspect
            figure_my_size(tops_sizes, myraw, "tops")
            figure_my_size(leggings_sizes, myraw, "leggings")
            figure_my_size(sports_bra_sizes, myraw, "sports-bra")
            figure_my_size(sports_jacket_sizes, myraw, "sports-jacket")
        end
        


        puts "All done!"
        puts "top sizes"
        puts tops_sizes.inspect
        puts "leggings sizes"
        puts leggings_sizes.inspect
        puts "sports bra sizes"
        puts sports_bra_sizes.inspect
        puts "sports-jacket sizes"
        puts sports_jacket_sizes.inspect



    end


    def setup_subscriptions_to_be_updated
        puts "Hi, setting up the subscriptions to be updated."
        puts "Deleting and resetting the table subscriptions_next_month_updated"
        SubscriptionsNextMonthUpdate.delete_all
        # Now reset index
        ActiveRecord::Base.connection.reset_pk_sequence!('subscriptions_next_month_updated')


        subs_update = "insert into subscriptions_next_month_updated (subscription_id, customer_id, updated_at, next_charge_scheduled_at, product_title, status, sku, shopify_product_id, shopify_variant_id, raw_line_items) select subscription_id, customer_id, updated_at, next_charge_scheduled_at, product_title, status, sku, shopify_product_id, shopify_variant_id, raw_line_item_properties from subscriptions where status = 'ACTIVE'"

        ActiveRecord::Base.connection.execute(subs_update)
        puts "All done"


    end

    def load_allocation_collections
        AllocationCollection.delete_all
        ActiveRecord::Base.connection.reset_pk_sequence!('allocation_collections')
        CSV.foreach('allocation_collections.csv', :encoding => 'ISO8859-1:utf-8', :headers => true) do |row|
            puts row.inspect
            myallocation = AllocationCollection.create(collection_name: row['collection_name'], collection_id: row['collection_id'], collection_product_id: row['collection_product_id'])

        end
        puts "Done with loading allocation_collections table"
    end

    def load_allocation_matching_products
        AllocationMatchingProduct.delete_all
        ActiveRecord::Base.connection.reset_pk_sequence!('allocation_matching_products')
        CSV.foreach('allocation_matching_products.csv', :encoding => 'ISO8859-1:utf-8', :headers => true) do |row|
            puts row.inspect
            my_matching = AllocationMatchingProduct.create(product_title: row['product_title'], incoming_product_id: row['incoming_product_id'], threepk: row['threepk'], outgoing_product_id: row['outgoing_product_id'])

        end
        puts "Done with loading allocation_matching_products table"

    end

    def load_allocation_alternate_products
        AllocationAlternateProduct.delete_all
        ActiveRecord::Base.connection.reset_pk_sequence!('allocation_alternate_products')
        CSV.foreach('allocation_alternate_products.csv', :encoding => 'ISO8859-1:utf-8', :headers => true) do |row|
            puts row.inspect
            my_alternate = AllocationAlternateProduct.create(product_title: row['product_title'], product_id: row['product_id'], variant_id: row['variant_id'], sku: row['sku'], product_collection: row['product_collection'])

        end
        puts "Done with loading allocation_alternate_products table"

    end

    def load_allocation_size_types
        AllocationSizeType.delete_all
        ActiveRecord::Base.connection.reset_pk_sequence!('allocation_size_types')
        CSV.foreach('allocation_size_types.csv', :encoding => 'ISO8859-1:utf-8', :headers => true) do |row|
            puts row.inspect
            myallocationsize = AllocationSizeType.create(collection_name: row['collection_name'], collection_id: row['collection_id'], collection_size_type: row['collection_size_type'])

        end
        puts "all done"
    end

    def load_allocation_inventory
        AllocationInventory.delete_all
        ActiveRecord::Base.connection.reset_pk_sequence!('allocation_inventory')
        CSV.foreach('allocation_inventory.csv', :encoding => 'ISO8859-1:utf-8', :headers => true) do |row|
            puts row.inspect
            myallocationinventory = AllocationInventory.create(collection_name: row['collection_name'], collection_id: row['collection_id'], inventory_available: row['inventory_available'], inventory_reserved: row['inventory_reserved'], size: row['size'], mytype: row['mytype'])

        end
        puts "all done"


    end

    def load_allocation_switchable_products_table
        AllocationSwitchableProduct.delete_all
        ActiveRecord::Base.connection.reset_pk_sequence!('allocation_switchable_products')
        CSV.foreach('switchable_products.csv', :encoding => 'ISO8859-1:utf-8', :headers => true) do |row|
            puts row.inspect
            myswitchable = AllocationSwitchableProduct.create(product_title: row['product_title'], shopify_product_id: row['shopify_product_id'], threepk: row['threepk'], prepaid: row['prepaid'])

        end
        puts "all done"


    end

    def determine_outlier_sizes(my_size_hash)
        contains_outlier_size = false
        my_size_hash.each do |key, value|
            puts "#{key}, #{value}"
            if  (value == "XS")
                contains_outlier_size = true
            end
        end
        return contains_outlier_size
    end

    def generate_random_index(mylength)
        return_length = rand(1..mylength)
        return return_length

    end

    def allocate_single_subscription(my_index, my_size_hash, sub)
        puts "Allocating single subscription"
        puts my_index.inspect
        puts my_size_hash.inspect
        puts sub.inspect

    end

    def background_allocate_subscriptions
        params = {"action" => "allocating subscriptions for next month", "recharge_change_header" => @my_staging_change_header}
        Resque.enqueue(BackgroundAllocate, params)
      end
  
      class BackgroundAllocate
        extend BackgroundHelper
  
        @queue = "background_allocation"
        def self.perform(params)
          # logger.info "UpdateSubscriptionProduct#perform params: #{params.inspect}"
          background_allocate_subscriptions(params)
        end
      end




    def allocate_subscriptions
        puts "Starting allocation"
        my_size_hash = Hash.new
        mysubs = SubscriptionsNextMonthUpdate.where("updated = ?", false)
        mysubs.each do |sub|
            my_size_hash = {}
            puts sub.inspect
            mysizes = SubLineItem.where("subscription_id = ?", sub.subscription_id)
            puts mysizes.inspect
            mysizes.each do |mys|
                case mys.name
                when "sports-jacket"
                    my_size_hash['sports-jacket'] = mys.value
                when "tops", "TOPS", "top"
                    my_size_hash['tops'] = mys.value
                when "sports-bra"
                    my_size_hash['sports-bra'] = mys.value
                when "leggings"
                    my_size_hash['leggings'] = mys.value
                end
            
            end
            puts my_size_hash.inspect
            if my_size_hash.length < 3
                puts "Can't do anything"
            else
                puts "Can allocate this subscription"
                my_index = 999
                contains_outlier = determine_outlier_sizes(my_size_hash)
                if contains_outlier
                    puts "must generate only random 1-3"
                    my_total_length = 3
                    my_index = generate_random_index(my_total_length)
                    puts "my_index = #{my_index}"
                else
                    puts "can generate random 1-5"
                    my_total_length = 5
                    my_index = generate_random_index(my_total_length)
                    puts "my_index = #{my_index}"
                end
                allocate_single_subscription(my_index, my_size_hash, sub)
                
            end

            

            #for now, my_size_hash < 3 means problem with subscription, do not allocate, mark broken
            #if my_size_hash has XL or XS in it, random number over first 3, otherwise all five


        end
        puts "Done"

    end

    


  end
end