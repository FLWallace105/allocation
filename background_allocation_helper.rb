#background_allocation_helper.rb

require 'dotenv'
require 'active_support/core_ext'
require 'sinatra/activerecord'
require 'httparty'
require_relative 'models/model'
require_relative 'lib/order_size'


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

        found_tops = false
        found_sports_bra = false
        found_leggings = false
        found_gloves = false
        sports_jacket_size = ""

        tops_size = ""
        leggings_size = ""
        gloves_size = ""

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
                sports_jacket_size = mystuff['value']
            end
            if mystuff['name'] == "tops"
                tops_size = mystuff['value']
                found_tops = true
                puts "ATTENTION -- Tops SIZE = #{tops_size}"
            end
            
            if mystuff['name'] == "sports-bra"
                found_sports_bra = true
            end
            if mystuff['name'] == "leggings"
                found_leggings = true
                leggings_size = mystuff['value']
                puts "Attention -- leggings_size = #{leggings_size}"
            end

            if mystuff['name'] == "gloves"
                found_gloves = true
            end

        end
        puts "my_line_items = #{my_line_items.inspect}"
        puts "---------"
        puts "tops_size = #{tops_size} and leggings_size = #{leggings_size}"
        puts "found_gloves = #{found_gloves}"

        if found_unique_id == false
            puts "We are adding the unique_identifier to the line item properties"
            my_line_items << { "name" => "unique_identifier", "value" => my_unique_id }

        end

        if found_tops == false
            puts "We are adding sports_jacket size to missing top size"
            my_line_items << { "name" => "tops", "value" => sports_jacket_size }
        end

        if found_sports_bra == false
            puts "We are adding sports_jacket size to missing sports-bra size"
            my_line_items << { "name" => "sports-bra", "value" => sports_jacket_size }
        end

        if found_sports_jacket == false
            puts "We are adding the sports-jacket size and using the tops size for this sub"
            my_line_items << {"name" => "sports-jacket", "value" => tops_size }

        end

        if found_gloves == false
            puts "We are adding legging size to missing gloves size"
            puts "leggings_size = #{leggings_size}"
            #case statement not working, brute force if statement
            if leggings_size == "S" || leggings_size == "XS"
                gloves_size = "S"
            elsif leggings_size == "M" || leggings_size == "L"
                gloves_size = "M"
            elsif leggings_size == "XL"
                gloves_size = "L"
            else
                gloves_size = "M"
            end

           # Floyd Wallace 4/25/19 -- no longer pushing glove sizes into subs
           # my_line_items << { "name" => "gloves", "value" => gloves_size}
           # puts "pushing glove sizes: #{gloves_size}"
           # puts my_line_items

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
        my_prod_type = AllocationSwitchableProduct.find_by_shopify_product_id(sub.shopify_product_id)
        if my_prod_type.nil?
            puts "Can't find the switchable product"
            #Mark the subscription as bad, don't process
            sub.bad_subscription = true
            sub.save!

        else
            puts "Switchable product prod_type = #{my_prod_type.prod_type}"
            puts my_local_collection.collection_product_id
            my_matching = AllocationMatchingProduct.where("incoming_product_id = ? and prod_type = ?", my_local_collection.collection_product_id.to_s, my_prod_type.prod_type.to_i).first
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
                
                puts "-----"
                puts "recharge_change_header = #{recharge_change_header}"

                #fix missing sizes
                if recharge_data['product_title'] =~ /2\sitem/i
                    #do nothing, don't add sizes
                else
                    new_json = OrderSize.add_missing_sub_size(recharge_data['properties'])
                    recharge_data['properties'] = new_json
                end
                puts "now sizes reflect:"
                puts recharge_data.inspect
                body = recharge_data.to_json
                puts body

                #exit
                #Comment out below for dry run
                my_update_sub = HTTParty.put("https://api.rechargeapps.com/subscriptions/#{sub.subscription_id}", :headers => recharge_change_header, :body => body, :timeout => 80)
                puts my_update_sub.inspect
                recharge_limit = my_update_sub.response["x-recharge-limit"]
                determine_limits(recharge_limit, 0.65)
                if my_update_sub.code == 200
                #if 7 > 3
                    sub.updated = true
                    time_updated = DateTime.now
                    time_updated_str = time_updated.strftime("%Y-%m-%d %H:%M:%S")
                    sub.processed_at = time_updated_str
                    sub.save!
                    puts "processed subscription_id #{sub.subscription_id}"
                    my_dry_run = SubNextMonthDryRun.create(subscription_id: sub.subscription_id, customer_id: sub.customer_id, updated_at: sub.updated_at, next_charge_scheduled_at: sub.next_charge_scheduled_at, product_title: recharge_data['product_title'], status: sub.status, sku: recharge_data['sku'], shopify_product_id: recharge_data['shopify_product_id'], shopify_variant_id: recharge_data['shopify_variant_id'], raw_line_items: recharge_data['properties'], updated: true, processed_at: sub.processed_at)
                else
                    sub.bad_subscription = true
                    sub.save!
                    puts "Cannot process subscription_id #{sub.subscription_id}"
                end
                puts "sent info to Recharge"
            end
            puts "Done handling a valid prod_type value"
            
        end
        puts "Done with processing the subscription"
        #exit
    end


    
    def determine_outlier_sizes(my_size_hash)
        contains_outlier_size = false
        my_size_hash.each do |key, value|
            puts "#{key}, #{value}"
            #if (value == "XS")
            #if  (value == "XS") || (value == "S") || (value == "XL")
            #    contains_outlier_size = true
            #end
        end
        return contains_outlier_size
    end

    def generate_random_index(mylength)
        return_length = rand(1..mylength)
        return return_length

    end

    def generate_exclude(my_index)
        temp_exclude = ""
        case my_index
        when 1
            temp_exclude = "tops"
        when 2
            temp_exclude = "sports-jacket"
        when 3
            temp_exclude = "sports-jacket"
        when 4
            temp_exclude = "sports-jacket"
        #when 5
        #    temp_exclude = "sports-jacket"
        else



        end
        return temp_exclude

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

        #Code Floyd Wallace 10/29
        #remove unwanted my_size_hash entries for two item subs
        if sub.product_title =~ /2\sitem/i
            case my_index
            when 1
                my_size_hash.delete("sports-bra")
            when 2
                my_size_hash.delete("sports-jacket")
            when 3
                my_size_hash.delete("sports-bra")
            when 4
                my_size_hash.delete("sports-bra")
            when 5
                my_size_hash.delete("sports-bra")

            else
                puts "Doing nothing for this two item sub"
            end

        end


        can_allocate = true
        my_local_collection = AllocationCollection.find_by_collection_id(my_index)
        my_size_hash.each do |k, v|
            puts "#{k}, #{v}"
            #if k != exclude && my_index > 1
            if k != exclude 
            mylocal_inventory = AllocationInventory.where("collection_id = ? and size = ? and mytype = ?", my_index, v, k).first
            puts mylocal_inventory.inspect
                if mylocal_inventory.inventory_available <= 0
                    can_allocate = false
                end
            #else
             #   puts "Excluding #{k}, #{v} from allocation calculations this collection!"
            #elsif my_index == 1 && k != "tops"
            #    mylocal_inventory = AllocationInventory.where("collection_id = ? and size = ? and mytype = ?", my_index, v, k).first
            #    puts mylocal_inventory.inspect
            #    if mylocal_inventory.inventory_available <= 0
            #        can_allocate = false
            #    end


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
                if k != exclude 
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

                #elsif my_index == 1 && k != "tops"
                #    mylocal_inventory = AllocationInventory.where("collection_id = ? and size = ? and mytype = ?", my_index, v, k).first
            
                    #Adjust inventory
                #    if sub.bad_subscription == false
                #        puts mylocal_inventory.inspect
                #        mylocal_inventory.inventory_available -= 1
                #        mylocal_inventory.inventory_reserved += 1
                #        mylocal_inventory.save!
                #    else
                #        puts "Not adjusting inventory, bad subscription"
                #    end
                
                
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
        puts "mysubs length = #{mysubs.length}"
        puts "here"
        mysubs.each do |sub|
            my_size_hash = {}
            puts sub.inspect
            #fix for missing sizes
            found_legging = false
            found_tops = false
            found_bra = false
            found_jacket = false
            legging_size = ""
            tops_size = ""
            bra_size = ""
            jacket_size = ""


            mysizes = SubLineItem.where("subscription_id = ?", sub.subscription_id)
            puts mysizes.inspect
            mysizes.each do |mys|
                case mys.name
                when "sports-jacket"
                    found_jacket = true
                    jacket_size = mys.value.upcase
                    my_size_hash['sports-jacket'] = mys.value.upcase
                when "tops", "TOPS", "top"
                    my_size_hash['tops'] = mys.value.upcase
                    found_tops = true
                    tops_size = mys.value.upcase
                when "sports-bra"
                    my_size_hash['sports-bra'] = mys.value.upcase
                    found_bra = true
                    bra_size = mys.value.upcase
                when "leggings"
                    my_size_hash['leggings'] = mys.value.upcase
                    found_legging = true
                    legging_size = mys.value.upcase
                end
            
            end

            #stuff in missing sizes
            if found_tops == false && found_jacket == true
                my_size_hash['tops'] =  jacket_size
            end

            if found_legging == false && found_tops == true
                my_size_hash['leggings'] =  tops_size
            end

            if found_bra == false && found_jacket == true
                my_size_hash['sports-bra'] = jacket_size
            end

            if found_jacket == false && found_tops == true
                my_size_hash['sports-jacket'] = tops_size
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
                my_exclude = generate_exclude(my_index)
                puts "my_exclude = #{my_exclude}"
                
                allocate_single_subscription(my_index, my_size_hash, sub, my_exclude,recharge_change_header )
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

    def overflow_subscriptions(recharge_change_header)
        #use Brooklyn index 2 for April 2019
        puts "Starting allocation"
        my_now = Time.now
        my_size_hash = Hash.new
        mysubs = SubscriptionsNextMonthUpdate.where("updated = ? and bad_subscription = ?", false, false)
        mysubs.each do |sub|
            my_size_hash = {}
            puts sub.inspect
            #fix for missing sizes
            found_legging = false
            found_tops = false
            found_bra = false
            legging_size = ""
            tops_size = ""
            bra_size = ""


            mysizes = SubLineItem.where("subscription_id = ?", sub.subscription_id)
            puts mysizes.inspect
            mysizes.each do |mys|
                case mys.name
                when "sports-jacket"
                    my_size_hash['sports-jacket'] = mys.value.upcase
                when "tops", "TOPS", "top"
                    my_size_hash['tops'] = mys.value.upcase
                    found_tops = true
                    tops_size = mys.value.upcase
                when "sports-bra"
                    my_size_hash['sports-bra'] = mys.value.upcase
                    found_bra = true
                    bra_size = mys.value.upcase
                when "leggings"
                    my_size_hash['leggings'] = mys.value.upcase
                    found_legging = true
                    legging_size = mys.value.upcase
                end
            
            end

            #stuff in missing sizes
            if found_tops == false && found_legging == true
                my_size_hash['tops'] =  legging_size
            end

            if found_legging == false && found_tops == true
                my_size_hash['leggings'] =  tops_size
            end

            if found_bra == false && found_legging == true
                my_size_hash['sports-bra'] = legging_size
            end

            if my_size_hash.length < 3
                puts "Can't do anything"
                sub.bad_subscription = true
                sub.save!
            else
                puts "Can allocate this subscription"
                my_index = 2
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
        end
    end

    def background_allocate_subscriptions(params)
        puts "Starting background allocation"
        puts params.inspect
        recharge_change_header = params['recharge_change_header']
        allocate_subscriptions(recharge_change_header)

        #uncomment for overflow and comment above for overflow
        #overflow_subscriptions(recharge_change_header)



    end



end