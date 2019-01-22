#background_allocation_helper.rb

require 'dotenv'
require 'active_support/core_ext'
require 'sinatra/activerecord'
require 'httparty'
require_relative 'models/model'


Dotenv.load

module BackgroundHelper

    def create_recharge_data(sub, my_alternate_product)
        found_collection = false
        found_unique_id = false
        found_sports_jacket = false
        tops_size = ""
        my_unique_id = SecureRandom.uuid
        my_line_items = sub.raw_line_items

        my_line_items.map do |mystuff|
            # puts "#{key}, #{value}"
            if mystuff['name'] == 'product_collection'
                mystuff['value'] = my_alternate_product.product_collection
                found_collection = true
            end
            if mystuff['name'] == 'unique_identifier'
                mystuff['value'] = my_unique_id
                found_unique_id = true
            end
            if mystuff['name'] == "sports-jacket"
                found_sports_jacket = true
            end
            if mystuff['name'] == "tops"
                tops_size = mystuff['value']
                puts "ATTENTION -- Tops SIZE = #{tops_size}"
            end
        end
        puts "my_line_items = #{my_line_items.inspect}"
        puts "---------"
        puts "tops_size = #{tops_size}"

        if found_unique_id == false
            puts "We are adding the unique_identifier to the line item properties"
            my_line_items << { "name" => "unique_identifier", "value" => my_unique_id }

        end

        if found_sports_jacket == false
            puts "We are adding the sports-bra size for the sports-jacket size"
            my_line_items << { "name" => "sports-jacket", "value" => tops_size}
        end

        if found_collection == false
            # only if I did not find the product_collection property in the line items do I need to add it
            puts "We are adding the product collection to the line item properties"
            my_line_items << { "name" => "product_collection", "value" => my_alternate_product.product_collection }
        end

        stuff_to_return = Hash.new
        #Gotta determine here if the original product for subscription is prepaid
        my_prod = AllocationSwitchableProduct.find_by_shopify_product_id(sub.shopify_product_id)
        #Double check for nil value
        puts my_prod.inspect
        puts "checking nil"
        


        if my_prod.nil?
            stuff_to_return = { "sku" => "skip"}
            
        else
            puts "my_prod  not nil"
            

        
            if my_prod.prepaid == true
                stuff_to_return = { "properties" => my_line_items }
                puts "here"
            else
                #puts "also here"
                #puts my_alternate_product.inspect
                stuff_to_return = { "sku" => my_alternate_product.sku, "product_title" => my_alternate_product.product_title, "shopify_product_id" => my_alternate_product.product_id, "shopify_variant_id" => my_alternate_product.variant_id, "properties" => my_line_items }
                #puts stuff_to_return.inspect
                #puts "Done here"
                
            end
            
            
        end
        return stuff_to_return
    end

    def background_update_sub(my_local_collection, sub)
        puts "Figuring what collection details to push to Recharge"
        puts my_local_collection.inspect
        puts sub.inspect
        my_threepk = AllocationSwitchableProduct.find_by_shopify_product_id(sub.shopify_product_id)
        if my_threepk.nil?
            puts "Can't find the switchable product"
            #Mark the subscription as bad, don't process

        else
            puts "Switchable product threepk = #{my_threepk.threepk}"
            puts my_local_collection.collection_product_id
            my_matching = AllocationMatchingProduct.where("incoming_product_id = ? and threepk = ?", my_local_collection.collection_product_id.to_s, my_threepk.threepk).first
            puts "my_matching = #{my_matching.inspect}"
            outgoing_product_id = my_matching.outgoing_product_id
            my_alternate_product = AllocationAlternateProduct.find_by_product_id(outgoing_product_id)
            puts "Alternate product = #{my_alternate_product.inspect}"

            recharge_data = create_recharge_data(sub, my_alternate_product)
            puts recharge_data.inspect
            if recharge_data['sku'] == "skip"
                puts "Skipping this one folks bad data in the subscription"
                #Mark the subscription as bad, don't process
            else
                puts "Here is the stuff to send to Recharge"
                puts recharge_data.inspect
            end

            exit
        end
        
    end


    def allocate_single_subscription(my_index, my_size_hash, sub)
        puts "Allocating single subscription"
        puts my_index.inspect
        puts my_size_hash.inspect
        puts sub.inspect

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

    def allocate_single_subscription(my_index, my_size_hash, sub, exclude)
        puts "Allocating single subscription"
        puts my_index.inspect
        puts my_size_hash.inspect
        puts sub.inspect
        can_allocate = true
        my_local_collection = AllocationCollection.find_by_collection_id(my_index)
        my_size_hash.each do |k, v|
            puts "#{k}, #{v}"
            if k != exclude
            mylocal_inventory = AllocationInventory.where("collection_id = ? and size = ? and mytype = ?", my_index, v, k).first
            puts mylocal_inventory.inspect
                if mylocal_inventory.inventory_available <= 0
                    can_allocate = false
                end
            else
                puts "Excluding #{k}, #{v} from allocation calculations this collection!"
            end
            
            
        end
        puts "Can we allocate to this collection #{my_local_collection.collection_name}  ? #{can_allocate}"
        if !can_allocate
            puts "can't allocate"
            #exit
        else
            puts "Allocating this subscription and doing inventory adjustment"
            #exit
            #allocate here
            my_size_hash.each do |k, v|
                puts "#{k}, #{v}"
                if k != exclude
                mylocal_inventory = AllocationInventory.where("collection_id = ? and size = ? and mytype = ?", my_index, v, k).first

                #Now adjust subscription, assume it has been updated
                #send to some method to update the subscription
                background_update_sub(my_local_collection, sub)
                exit
                

                #Adjust inventory
                puts mylocal_inventory.inspect
                mylocal_inventory.inventory_available -= 1
                mylocal_inventory.inventory_reserved += 1
                mylocal_inventory.save!
                
                sub.updated = true
                time_updated = DateTime.now
                time_updated_str = time_updated.strftime("%Y-%m-%d %H:%M:%S")
                sub.processed_at = time_updated_str
                sub.save!

                
                else
                    puts "Excluding #{k}, #{v} from inventory calcs this collection!"
                end
                puts "Done inventory adjustment"
                
            end


        end
    end


    def allocate_subscriptions
        puts "Starting allocation"
        my_size_hash = Hash.new
        mysubs = SubscriptionsNextMonthUpdate.where("updated = ? and bad_subscription = ?", false, false)
        mysubs.each do |sub|
            my_size_hash = {}
            puts sub.inspect
            mysizes = SubLineItem.where("subscription_id = ?", sub.subscription_id)
            puts mysizes.inspect
            mysizes.each do |mys|
                case mys.name
                when "sports-jacket"
                    my_size_hash['sports-jacket'] = mys.value.upcase
                when "tops", "TOPS", "top"
                    my_size_hash['tops'] = mys.value.upcase
                when "sports-bra"
                    my_size_hash['sports-bra'] = mys.value.upcase
                when "leggings"
                    my_size_hash['leggings'] = mys.value.upcase
                end
            
            end
            puts my_size_hash.inspect
            if my_size_hash.length < 3
                puts "Can't do anything"
                sub.bad_subscription = true
                sub.save!
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
                allocate_single_subscription(my_index, my_size_hash, sub, "sports-jacket")
                
            end

            

            #for now, my_size_hash < 3 means problem with subscription, do not allocate, mark broken
            #if my_size_hash has XL or XS in it, random number over first 3, otherwise all five


        end
        puts "Done"

    end

    def background_allocate_subscriptions(params)
        puts "Starting background allocation"
        puts params.inspect
        allocate_subscriptions



    end



end