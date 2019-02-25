#background_allocation_helper.rb

require 'dotenv'
require 'active_support/core_ext'
require 'sinatra/activerecord'
require 'httparty'
require_relative 'models/model'


Dotenv.load

module BackgroundHelper

    def determine_limits(recharge_header, limit)
        puts "recharge_header = #{recharge_header}"
        my_numbers = recharge_header.split("/")
        my_numerator = my_numbers[0].to_f
        my_denominator = my_numbers[1].to_f
        my_limits = (my_numerator/ my_denominator)
        puts "We are using #{my_limits} % of our API calls"
        if my_limits > limit
            puts "Sleeping 15 seconds"
            sleep 15
        else
            puts "not sleeping at all"
        end
  
      end


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
            sub.bad_subscription = true
            sub.save!
            stuff_to_return = { "sku" => "skip"}
            
        else
            puts "my_prod  not nil"
            
            puts "my_prod is prepaid #{my_prod.prepaid?}"
        
            if my_prod.prepaid?
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

    def background_update_sub(my_local_collection, sub, recharge_change_header)
        puts "Figuring what collection details to push to Recharge"
        puts my_local_collection.inspect
        puts sub.inspect
        my_threepk = AllocationSwitchableProduct.find_by_shopify_product_id(sub.shopify_product_id)
        if my_threepk.nil?
            puts "Can't find the switchable product"
            #Mark the subscription as bad, don't process
            sub.bad_subscription = true
            sub.save!

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
                #already Marked the subscription as bad, don't process
            else
                puts "Here is the stuff to send to Recharge"
                puts recharge_data.inspect
                body = recharge_data.to_json
                puts body
                puts "-----"
                puts "recharge_change_header = #{recharge_change_header}"
                my_update_sub = HTTParty.put("https://api.rechargeapps.com/subscriptions/#{sub.subscription_id}", :headers => recharge_change_header, :body => body, :timeout => 80)
                puts my_update_sub.inspect
                recharge_limit = my_update_sub.response["x-recharge-limit"]
                determine_limits(recharge_limit, 0.65)
                if my_update_sub.code == 200
                    sub.updated = true
                    time_updated = DateTime.now
                    time_updated_str = time_updated.strftime("%Y-%m-%d %H:%M:%S")
                    sub.processed_at = time_updated_str
                    sub.save!
                    puts "processed subscription_id #{sub.subscription_id}"
                else
                    sub.bad_subscription = true
                    sub.save!
                    puts "Cannot process subscription_id #{sub.subscription_id}"
                end
                puts "sent info to Recharge"
            end
            puts "Done handling a valid threepk value"
            
        end
        puts "Done with processing the subscription"
        #exit
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

    def allocate_single_subscription(my_index, my_size_hash, sub, exclude, recharge_change_header)
        puts "Allocating single subscription"
        puts my_index.inspect
        puts my_size_hash.inspect
        puts sub.inspect
        #my_index == 1 is the first collection, sports-jacket no top, remove tops from my_size_hash
        #if my_index == 1
        #    my_size_hash.delete(:tops)
        #end


        can_allocate = true
        my_local_collection = AllocationCollection.find_by_collection_id(my_index)
        my_size_hash.each do |k, v|
            puts "#{k}, #{v}"
            if k != exclude && my_index > 1
            mylocal_inventory = AllocationInventory.where("collection_id = ? and size = ? and mytype = ?", my_index, v, k).first
            puts mylocal_inventory.inspect
                if mylocal_inventory.inventory_available <= 0
                    can_allocate = false
                end
            #else
             #   puts "Excluding #{k}, #{v} from allocation calculations this collection!"
            elsif my_index == 1 && k != "tops"
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
            background_update_sub(my_local_collection, sub, recharge_change_header)
            #above uncomment for real run and allocation

            #below is for testing only dry run
            #sub.updated = true
            #sub.save!
            #exit
            #allocate here
            my_size_hash.each do |k, v|
                puts "#{k}, #{v}"
                if k != exclude && my_index > 1
                    mylocal_inventory = AllocationInventory.where("collection_id = ? and size = ? and mytype = ?", my_index, v, k).first

                    #Adjust inventory
                    if sub.bad_subscription == false
                        puts mylocal_inventory.inspect
                        mylocal_inventory.inventory_available -= 1
                        mylocal_inventory.inventory_reserved += 1
                        mylocal_inventory.save!
                    else
                        puts "Not adjusting inventory, bad subscription"
                    end

                elsif my_index == 1 && k != "tops"
                    mylocal_inventory = AllocationInventory.where("collection_id = ? and size = ? and mytype = ?", my_index, v, k).first
            
                    #Adjust inventory
                    if sub.bad_subscription == false
                        puts mylocal_inventory.inspect
                        mylocal_inventory.inventory_available -= 1
                        mylocal_inventory.inventory_reserved += 1
                        mylocal_inventory.save!
                    else
                        puts "Not adjusting inventory, bad subscription"
                    end
                
                
                else
                    puts "Excluding #{k}, #{v} from inventory calcs this collection!"
                end
                puts "Done inventory adjustment"
                
            end


        end
    end


    def allocate_subscriptions(recharge_change_header)
        puts "Starting allocation"
        my_now = Time.now
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
                    puts "can generate random 1-4"
                    my_total_length = 4
                    my_index = generate_random_index(my_total_length)
                    puts "my_index = #{my_index}"
                end
                allocate_single_subscription(my_index, my_size_hash, sub, "sports-jacket",recharge_change_header )
                puts "done with a subscription!"
                #see if running more than eight minutes
                my_current = Time.now
                duration = (my_current - my_now).ceil
                puts "Been running #{duration} seconds"
                

                if duration > 480
                    puts "Been running more than 8 minutes must exit"
                    break
                end
                
            end

            

            #for now, my_size_hash < 3 means problem with subscription, do not allocate, mark broken
            #if my_size_hash has XL or XS in it, random number over first 3, otherwise all five


        end
        puts "Done"

    end

    def background_allocate_subscriptions(params)
        puts "Starting background allocation"
        puts params.inspect
        recharge_change_header = params['recharge_change_header']
        allocate_subscriptions(recharge_change_header)



    end



end