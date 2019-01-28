#background_order_helper.rb

require 'dotenv'
require 'active_support/core_ext'
require 'sinatra/activerecord'
require 'httparty'
require_relative 'models/model'


Dotenv.load

module BackgroundOrderHelper

    def create_recharge_data(order, my_alternate_product)
        puts "got here"
        puts my_alternate_product.inspect
        found_collection = false
        found_unique_id = false
        found_sports_jacket = false
        tops_size = ""
        
        my_line_items = order.line_items
        puts "-------------"
        puts my_line_items.inspect
        puts "--------------"
        my_properties = Array.new
        local_product_id = 999
        local_variant_id = 999
        quantity = 1
        title = "funky"
        my_line_items.each do |myline|
            puts myline.inspect
            local_product_id = myline['shopify_product_id']
            local_variant_id = myline['shopify_variant_id']
            quantity = myline['quantity']
            title = myline['title']
            #puts myline['properties']
            my_properties = myline['properties']
            
            #my_properties.map do |mystuff|
            #     #puts "#{key}, #{value}"
            #    if mystuff['name'] == 'product_collection'
             #       mystuff['value'] = my_alternate_product.product_collection 
             #   end                    
            #end
            #puts my_properties.inspect
            #my_recharge_line_items << my_properties
        end
        puts my_properties.inspect
        my_properties.map do |mystuff|
            #puts "#{key}, #{value}"
            puts mystuff.inspect
            if mystuff['name'] == 'product_collection'
                mystuff['value'] = my_alternate_product.collection_name 
            end                    
        end
        puts "*************"
        puts my_properties.inspect
        puts "*****************"
        
        my_data = { "line_items" => [ { "properties" => my_properties, "product_id" => 1635509436467, "variant_id" => 15880479965235, "quantity" => 1, "title" => title}]}
        #puts my_line_items
        puts "Here is what we will return to send to ReCharge: #{my_data}"
        return my_data
        


    end



    def find_product_id_order(my_line_items)
        my_order_product_id_hash = Hash.new
        my_line_items.each do |myline|
            puts myline['properties'].inspect
            myattr = myline['properties']
            myattr.each do |mya|
                puts mya.inspect
                if mya['name'] == "product_id"
                    my_order_product_id_hash ['product_id'] = mya['value']
                end
                

            end
        end
        return my_order_product_id_hash
    end

    def background_update_order(my_local_collection, order, recharge_change_header)
        puts "Figuring what collection details to push to Recharge"
        puts my_local_collection.inspect
        puts "-----------------"
        puts order.inspect
        my_line_items = order.line_items
        my_order_product_id_hash = find_product_id_order(my_line_items)
        puts my_line_items.inspect
        puts my_order_product_id_hash.inspect
        puts "-----------------"
        #exit
        my_threepk = AllocationSwitchableProduct.find_by_shopify_product_id(my_order_product_id_hash['product_id'])
        if my_threepk.nil?
            puts "Can't find the switchable product"
            #Mark the subscription as bad, don't process
            order.bad_order = true
            order.save!

        else
            puts "Switchable product threepk = #{my_threepk.threepk}"
            puts my_local_collection.collection_product_id
            my_matching = AllocationMatchingProduct.where("incoming_product_id = ? and threepk = ?", my_local_collection.collection_product_id.to_s, my_threepk.threepk).first
            puts "my_matching = #{my_matching.inspect}"
            outgoing_product_id = my_matching.outgoing_product_id
            my_alternate_product = AllocationAlternateProduct.find_by_product_id(outgoing_product_id)
            puts "Alternate product = #{my_alternate_product.inspect}"

            
            recharge_data = create_recharge_data(order, my_alternate_product)
            puts recharge_data.inspect
            


            my_update_order = HTTParty.put("https://api.rechargeapps.com/orders/#{order.order_id}", :headers => recharge_change_header, :body =>recharge_data.to_json, :timeout => 80)
            puts my_update_order.inspect

            if my_update_order.code == 200
                order.updated = true
                
                time_updated = DateTime.now
                time_updated_str = time_updated.strftime("%Y-%m-%d %H:%M:%S")
                order.updated_at = time_updated_str
                order.save

            else
                puts "WE could not update the order order_id = #{my_order_id}"

            end


            
            
            
        end
        
    end

    def quick_fix_staging(my_local_collection, order, recharge_change_header)
        puts "I am here"
        recharge_data = create_recharge_data(order, my_local_collection)
        puts recharge_data.inspect
            


        my_update_order = HTTParty.put("https://api.rechargeapps.com/orders/#{order.order_id}", :headers => recharge_change_header, :body =>recharge_data.to_json, :timeout => 80)
        puts my_update_order.inspect
        puts "Got this back from ReCharge"
        #if my_update_order.parsed_response['errors']
        #    order.updated = true
        #        
        #    time_updated = DateTime.now
        #    time_updated_str = time_updated.strftime("%Y-%m-%d %H:%M:%S")
        #    order.updated_at = time_updated_str
        #    order.save

       # else
        #    puts "WE could not update the order order_id = #{my_order_id}"

       # end

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

    def allocate_single_order(my_index, my_size_hash, order, exclude, recharge_change_header)
        puts "Allocating single subscription"
        puts my_index.inspect
        puts my_size_hash.inspect
        puts order.inspect
        can_allocate = true
        my_local_collection = AllocationCollection.find_by_collection_id(my_index)
        #temporarily turn off these checks for Staging with stuff mucked up
        #my_size_hash.each do |k, v|
        #    puts "#{k}, #{v}"
        #    if k != exclude
        #    mylocal_inventory = AllocationInventory.where("collection_id = ? and size = ? and mytype = ?", my_index, v, k).first
        #    puts mylocal_inventory.inspect
        #        if mylocal_inventory.inventory_available <= 0
        #            can_allocate = false
        #        end
        #    else
        #        puts "Excluding #{k}, #{v} from allocation calculations this collection!"
        #    end
                  
        #end
        puts "Can we allocate to this collection #{my_local_collection.collection_name}  ? #{can_allocate}"
        if !can_allocate
            puts "can't allocate"
            #exit
        else
            puts "Allocating this subscription and doing inventory adjustment"
            #exit
            #allocate here
            #commented out, Neville's migration hosed data
            #background_update_order(my_local_collection, order, recharge_change_header)
            quick_fix_staging(my_local_collection, order, recharge_change_header)
            
           # my_size_hash.each do |k, v|
            #    puts "#{k}, #{v}"
            #    if k != exclude
           #     mylocal_inventory = AllocationInventory.where("collection_id = ? and size = ? and mytype = ?", my_index, v, k).first

                #Now adjust subscription, assume it has been updated
                #send to some method to update the subscription
                
                

                #Adjust inventory
                #puts mylocal_inventory.inspect
                #mylocal_inventory.inventory_available -= 1
                #mylocal_inventory.inventory_reserved += 1
                #mylocal_inventory.save!
                
                

                
           #     else
            #        puts "Excluding #{k}, #{v} from inventory calcs this collection!"
            #    end
            #    puts "Done inventory adjustment"
                
           # end


        end
    end



    def allocate_orders(recharge_change_header)
        puts "Starting allocation"
        my_now = Time.now
        my_size_hash = Hash.new
        myorders = OrdersNextMonthUpdate.where("updated = ? and bad_order = ?", false, false)
        myorders.each do |myord|
            puts myord.inspect
            my_size_hash = Hash.new
            my_line_items = myord.line_items
            #puts my_line_items.inspect
            my_line_items.each do |myline|
                puts myline['properties'].inspect
                myattr = myline['properties']
                myattr.each do |mya|
                    puts mya.inspect
                    case mya['name']
                    when "sports-jacket"
                        my_size_hash['sports-jacket'] = mya['value'].upcase
                    when "tops", "TOPS", "top"
                        my_size_hash['tops'] = mya['value'].upcase
                    when "sports-bra"
                        my_size_hash['sports-bra'] = mya['value'].upcase
                    when "leggings"
                        my_size_hash['leggings'] = mya['value'].upcase
                    end

                end
            end
            puts "my_size_hash = #{my_size_hash}"
            if my_size_hash.length < 3
                puts "Can't do anything"
                myord.bad_order = true
                myord.save!
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
                allocate_single_order(my_index, my_size_hash, myord, "sports-jacket",recharge_change_header )
                puts "done with one order"
                
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


    def background_allocate_orders(params)
        puts "Background allocating prepaid orders"
        puts params.inspect
        recharge_change_header = params['recharge_change_header']
        allocate_orders(recharge_change_header)

    end


end