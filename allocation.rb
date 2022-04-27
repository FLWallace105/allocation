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
require_relative 'background_order_helper'
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

    def bad_product_collections
        my_bad_product_collections_subs = [' Posies In Paris - 3 Items', '3 Months - 2 Items', '3 Months - 3 Items', '3 Months - 5 Items', 'Purple Rain - 5 Items']
        my_bad_product_collection_orders = ['Ellie Picks', nil]

        File.delete('bad_product_collections.csv') if File.exist?('bad_product_collections.csv')
        #Headers for CSV
        column_header = ["subscription_id", "email", "product_collection"]
        CSV.open('bad_product_collections.csv','a+', :write_headers=> true, :headers => column_header) do |hdr|
            column_header = nil

        my_bad_product_collections_subs.each do |myb|
            my_prod_coll = SubCollectionSize.where("product_collection = ?",myb )
            my_prod_coll.each do |myprd|
                #puts myprd.inspect
                subscription_id = myprd.subscription_id
                my_subscription = Subscription.find_by_subscription_id(subscription_id)
                #puts my_subscription.inspect
                puts "#{my_subscription.subscription_id}, #{my_subscription.email}, #{myb}"
                csv_data_out = [my_subscription.subscription_id, my_subscription.email,myb ]
                hdr << csv_data_out

            end
        end
        csv_data_out = ["------ ORDERS ----------" ]
        hdr << csv_data_out
        csv_data_out = ["order_id", "scheduled_at", "email", "product_collection" ]
        hdr << csv_data_out

        my_bad_product_collection_orders.each do |mybad|
            my_prod_coll = OrderCollectionSize.where("product_collection = ?", mybad)
            my_prod_coll.each do |myprd|
                #puts myprd.inspect
                order_id = myprd.order_id
                my_order = Order.find_by_order_id(order_id)
                puts my_order.inspect
                csv_data_out = [my_order.order_id, my_order.scheduled_at, my_order.email, mybad ]
                hdr << csv_data_out
            end

        end

        my_orders = OrderCollectionSize.where("product_collection is null")
        my_orders.each do |ord|
            puts ord.inspect
            order_id = ord.order_id
            my_order = Order.find_by_order_id(order_id)
            puts my_order.inspect
            if my_order.status == 'QUEUED' && my_order.is_prepaid  == 1
                csv_data_out = [my_order.order_id, my_order.scheduled_at, my_order.email, "null product collection" ]
                hdr << csv_data_out
            end

        end

        end #csv
    end

    def summary_product_collection
        puts "Starting Summary Product Collection Assignments for Next Month"
        my_end_month = Date.today.end_of_month
        my_end_month_str = my_end_month.strftime("%Y-%m-%d")
        my_end_month_str = "2022-03-31"
        puts "End of the month = #{my_end_month_str}"
        my_start_month_plus = Date.today 
        my_start_month_plus = my_start_month_plus >> 1
        my_start_month_plus = my_start_month_plus.end_of_month + 1
        my_start_month_plus_str = my_start_month_plus.strftime("%Y-%m-%d")
        my_start_month_plus_str = "2022-05-01"
        puts "my start_month_plus_str = #{my_start_month_plus_str}"

        my_sub_counts = "select count(sub_collection_sizes.id), sub_collection_sizes.product_collection from sub_collection_sizes where DATE(sub_collection_sizes.next_charge_scheduled_at) > \'#{my_end_month_str}\' and DATE(sub_collection_sizes.next_charge_scheduled_at) < \'#{my_start_month_plus_str}\'  group by sub_collection_sizes.product_collection order by sub_collection_sizes.product_collection asc "

        sub_product_collections = ActiveRecord::Base.connection.execute(my_sub_counts).values
        puts sub_product_collections.inspect

        my_order_counts = "select count(orders.order_id), order_collection_sizes.product_collection from order_collection_sizes, orders where order_collection_sizes.order_id = orders.order_id and orders.status = 'QUEUED' and orders.scheduled_at > \'#{my_end_month_str}\' and orders.scheduled_at < \'#{my_start_month_plus_str}\' and orders.is_prepaid = '1' group by order_collection_sizes.product_collection order by order_collection_sizes.product_collection asc "

        order_product_collections = ActiveRecord::Base.connection.execute(my_order_counts).values
        puts order_product_collections.inspect

        sub_product_collections.each do |mysub|
            puts mysub.inspect

        end


        

        #delete old file
        File.delete('allocation_next_month.csv') if File.exist?('allocation_next_month.csv')
        #Headers for CSV
        column_header = ["count", "product_collection"]
        CSV.open('allocation_next_month.csv','a+', :write_headers=> true, :headers => column_header) do |hdr|
            column_header = nil
            
            sub_product_collections.each do |mysub|
                puts mysub.inspect
                csv_data_out = mysub
                hdr << csv_data_out
    
            end
            puts "-------- Now Orders --------"
            hdr << ["-------- Now Orders --------"]
            order_product_collections.each do |myord|
                puts myord.inspect
                csv_data_out = myord
                hdr << csv_data_out

            end


            

        end





    end


    def figure_size_counts
        puts "Howdy figuring size counts"
        #Generate Initial Raw Size Totals

        RawSizeTotal.delete_all
        # Now reset index
        ActiveRecord::Base.connection.reset_pk_sequence!('raw_size_totals')

        my_sub_count = Subscription.all.count
        puts "we have #{my_sub_count} subs"
        

        size_count_sql = "insert into raw_size_totals (size_count, size_name, size_value) select count(subscriptions.id), sub_line_items.name, sub_line_items.value from subscriptions, sub_line_items where subscriptions.subscription_id = sub_line_items.subscription_id and subscriptions.status = 'ACTIVE' and (sub_line_items.name = 'leggings' or sub_line_items.name = 'sports-bra' or sub_line_items.name = 'tops' or sub_line_items.name = 'sports-jacket') group by sub_line_items.name, sub_line_items.value"

        new_size_count_sql = "insert into raw_size_totals (size_count, size_name, size_value) select count(subscriptions.id), sub_line_items.name, sub_line_items.value from subscriptions, sub_line_items where subscriptions.subscription_id = sub_line_items.subscription_id and subscriptions.status = 'ACTIVE' and subscriptions.product_title not ilike '3%month%' and subscriptions.next_charge_scheduled_at is not null and (sub_line_items.name = 'leggings' or sub_line_items.name = 'sports-bra' or sub_line_items.name = 'tops' or sub_line_items.name = 'sports-jacket') group by sub_line_items.name, sub_line_items.value"

        ActiveRecord::Base.connection.execute(new_size_count_sql)

        


    end

    def figure_order_size_counts
        puts "Howdy figuring size counts ORDERS"
        #Generate Initial Raw Size Totals

        my_end_month = Date.today.end_of_month
        my_end_month_str = my_end_month.strftime("%Y-%m-%d")
        puts "End of the month = #{my_end_month_str}"
        my_start_month_plus = Date.today 
        my_start_month_plus = my_start_month_plus >> 1
        my_start_month_plus = my_start_month_plus.end_of_month + 1
        my_start_month_plus_str = my_start_month_plus.strftime("%Y-%m-%d")
        puts "my start_month_plus_str = #{my_start_month_plus_str}"


        RawSizeTotal.delete_all
        # Now reset index
        ActiveRecord::Base.connection.reset_pk_sequence!('raw_size_totals')  
        new_size_count_sql = "insert into raw_size_totals (size_count, size_name, size_value) select count(orders.id), order_line_items_variable.name, order_line_items_variable.value from orders, order_line_items_variable where orders.is_prepaid = 1 and orders.order_id = order_line_items_variable.order_id and orders.scheduled_at > \'#{my_end_month_str}\' and orders.scheduled_at < \'#{my_start_month_plus_str}\' and (order_line_items_variable.name = 'leggings' or order_line_items_variable.name = 'sports-bra' or order_line_items_variable.name = 'tops' or order_line_items_variable.name = 'sports-jacket') group by order_line_items_variable.name, order_line_items_variable.value"

        ActiveRecord::Base.connection.execute(new_size_count_sql)

        #now get subscriptions that will charge this month or next month, assume charge will be successful
        new_size_count_prepaid_sql = "insert into raw_size_totals (size_count, size_name, size_value) select count(subscriptions.id), sub_line_items.name, sub_line_items.value from subscriptions, sub_line_items where subscriptions.subscription_id = sub_line_items.subscription_id and subscriptions.status = 'ACTIVE' and subscriptions.product_title  ilike '3%month%' and subscriptions.next_charge_scheduled_at > \'#{my_end_month_str}\' and subscriptions.next_charge_scheduled_at < \'#{my_start_month_plus_str}\' and (sub_line_items.name = 'leggings' or sub_line_items.name = 'sports-bra' or sub_line_items.name = 'tops' or sub_line_items.name = 'sports-jacket') group by sub_line_items.name, sub_line_items.value"

        ActiveRecord::Base.connection.execute(new_size_count_prepaid_sql)



    end

    def figure_null_sub_size_counts

        RawSizeTotal.delete_all
        # Now reset index
        ActiveRecord::Base.connection.reset_pk_sequence!('raw_size_totals')

        
        new_size_count_sql = "insert into raw_size_totals (size_count, size_name, size_value) select count(subscriptions.id), sub_line_items.name, sub_line_items.value from subscriptions, sub_line_items where subscriptions.subscription_id = sub_line_items.subscription_id and subscriptions.status = 'ACTIVE' and subscriptions.next_charge_scheduled_at is null and (sub_line_items.name = 'leggings' or sub_line_items.name = 'sports-bra' or sub_line_items.name = 'tops' or sub_line_items.name = 'sports-jacket') group by sub_line_items.name, sub_line_items.value"

        ActiveRecord::Base.connection.execute(new_size_count_sql)


    end


    def figure_prepaid_charging_next_month

        my_end_month = Date.today.end_of_month
        my_end_month_str = my_end_month.strftime("%Y-%m-%d")
        puts "End of the month = #{my_end_month_str}"
        my_start_month_plus = Date.today 
        my_start_month_plus = my_start_month_plus >> 1
        my_start_month_plus = my_start_month_plus.end_of_month + 1
        my_start_month_plus_str = my_start_month_plus.strftime("%Y-%m-%d")
        puts "my start_month_plus_str = #{my_start_month_plus_str}"


        RawSizeTotal.delete_all
        # Now reset index
        ActiveRecord::Base.connection.reset_pk_sequence!('raw_size_totals')
        new_size_count_sql = "insert into raw_size_totals (size_count, size_name, size_value) select count(subscriptions.id), sub_line_items.name, sub_line_items.value from subscriptions, sub_line_items where subscriptions.subscription_id = sub_line_items.subscription_id and subscriptions.status = 'ACTIVE' and ( subscriptions.product_title  ilike '3%month%'  or subscriptions.charge_interval_frequency = 3 )and subscriptions.next_charge_scheduled_at > \'#{my_end_month_str}\' and subscriptions.next_charge_scheduled_at < \'#{my_start_month_plus_str}\' and (sub_line_items.name = 'leggings' or sub_line_items.name = 'sports-bra' or sub_line_items.name = 'tops' or sub_line_items.name = 'sports-jacket') group by sub_line_items.name, sub_line_items.value"

        

        ActiveRecord::Base.connection.execute(new_size_count_sql)

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

        when "XXL", "xxl", "xxL"
            my_sizes["XXL"] = my_sizes["XXL"] + size_count 
        
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
        puts "Getting real size counts SUBS"
        figure_size_counts
        #start with tops
        tops_sizes = {"XS" => 0, "S" => 0, "M" => 0, "L" => 0, "XL" => 0, "XXL" => 0}
        leggings_sizes = {"XS" => 0, "S" => 0, "M" => 0, "L" => 0, "XL" => 0, "XXL" => 0}
        sports_bra_sizes = {"XS" => 0, "S" => 0, "M" => 0, "L" => 0, "XL" => 0, "XXL" => 0}
        sports_jacket_sizes = {"XS" => 0, "S" => 0, "M" => 0, "L" => 0, "XL" => 0, "XXL" => 0}

        my_raw_sizes = RawSizeTotal.all
        my_raw_sizes.each do |myraw|
            puts myraw.inspect
            figure_my_size(tops_sizes, myraw, "tops")
            figure_my_size(leggings_sizes, myraw, "leggings")
            figure_my_size(sports_bra_sizes, myraw, "sports-bra")
            figure_my_size(sports_jacket_sizes, myraw, "sports-jacket")
        end
        


        puts "All done for Subscriptions!"
        puts "top sizes"
        puts tops_sizes.inspect
        puts "leggings sizes"
        puts leggings_sizes.inspect
        puts "sports bra sizes"
        puts sports_bra_sizes.inspect
        puts "sports-jacket sizes"
        puts sports_jacket_sizes.inspect

        #Write file
        #column_header = ["order_name", "first_name", "last_name", "created_at", "billing_address1", "billing_address2", "city", "state", "zip", "email", "sku"]
        File.delete('size_count.csv') if File.exist?('size_count.csv')
        size_file = File.open('size_count.csv', 'w')
        size_file.write("SUBSCRIPTION SIZES\n")
        size_file.write("Tops\n")
        size_file.write("XS,S,M,L,XL,XXL\n")
        size_array = ["XS", "S", "M", "L", "XL", "XXL"]
        size_array.each do |mys|
            if mys != "XXL"
                size_file.write("#{tops_sizes[mys]},")
            else
                size_file.write("#{tops_sizes[mys]}\n")
            end
        end
        size_file.write("Leggings\n")
        size_file.write("XS,S,M,L,XL,XXL\n")
        size_array.each do |mys|
            if mys != "XXL"
                size_file.write("#{leggings_sizes[mys]},")
            else
                size_file.write("#{leggings_sizes[mys]}\n")
            end
        end
        size_file.write("Sports Bra\n")
        size_file.write("XS,S,M,L,XL,XXL\n")
        size_array.each do |mys|
            if mys != "XXL"
                size_file.write("#{sports_bra_sizes[mys]},")
            else
                size_file.write("#{sports_bra_sizes[mys]}\n")
            end
        end
        size_file.write("Sports Jacket\n")
        size_file.write("XS,S,M,L,XL,XXL\n")
        size_array.each do |mys|
            if mys != "XXL"
                size_file.write("#{sports_jacket_sizes[mys]},")
            else
                size_file.write("#{sports_jacket_sizes[mys]}\n")
            end
        end

        

        #Orders
        figure_order_size_counts
        puts "Getting real size counts ORDERS"
        
        #start with tops
        tops_sizes = {"XS" => 0, "S" => 0, "M" => 0, "L" => 0, "XL" => 0, "XXL" => 0}
        leggings_sizes = {"XS" => 0, "S" => 0, "M" => 0, "L" => 0, "XL" => 0, "XXL" => 0}
        sports_bra_sizes = {"XS" => 0, "S" => 0, "M" => 0, "L" => 0, "XL" => 0, "XXL" => 0}
        sports_jacket_sizes = {"XS" => 0, "S" => 0, "M" => 0, "L" => 0, "XL" => 0, "XXL" => 0}

        my_raw_sizes = RawSizeTotal.all
        my_raw_sizes.each do |myraw|
            puts myraw.inspect
            figure_my_size(tops_sizes, myraw, "tops")
            figure_my_size(leggings_sizes, myraw, "leggings")
            figure_my_size(sports_bra_sizes, myraw, "sports-bra")
            figure_my_size(sports_jacket_sizes, myraw, "sports-jacket")
        end
        


        puts "All done for ORDERS!"
        puts "top sizes"
        puts tops_sizes.inspect
        puts "leggings sizes"
        puts leggings_sizes.inspect
        puts "sports bra sizes"
        puts sports_bra_sizes.inspect
        puts "sports-jacket sizes"
        puts sports_jacket_sizes.inspect

        size_file.write("ORDERS SIZES\n")
        size_file.write("Tops\n")
        size_file.write("XS,S,M,L,XL,XXL\n")
        size_array = ["XS", "S", "M", "L", "XL", "XXL"]
        size_array.each do |mys|
            if mys != "XXL"
                size_file.write("#{tops_sizes[mys]},")
            else
                size_file.write("#{tops_sizes[mys]}\n")
            end
        end
        size_file.write("Leggings\n")
        size_file.write("XS,S,M,L,XL,XXL\n")
        size_array.each do |mys|
            if mys != "XXL"
                size_file.write("#{leggings_sizes[mys]},")
            else
                size_file.write("#{leggings_sizes[mys]}\n")
            end
        end
        size_file.write("Sports Bra\n")
        size_file.write("XS,S,M,L,XL,XXL\n")
        size_array.each do |mys|
            if mys != "XXL"
                size_file.write("#{sports_bra_sizes[mys]},")
            else
                size_file.write("#{sports_bra_sizes[mys]}\n")
            end
        end
        size_file.write("Sports Jacket\n")
        size_file.write("XS,S,M,L,XL,XXL\n")
        size_array.each do |mys|
            if mys != "XXL"
                size_file.write("#{sports_jacket_sizes[mys]},")
            else
                size_file.write("#{sports_jacket_sizes[mys]}\n")
            end
        end

    #null value subs
    figure_null_sub_size_counts
    puts "Getting real size counts NULL VALUE SUBS"
    
    #start with tops
    tops_sizes = {"XS" => 0, "S" => 0, "M" => 0, "L" => 0, "XL" => 0, "XXL" => 0}
    leggings_sizes = {"XS" => 0, "S" => 0, "M" => 0, "L" => 0, "XL" => 0, "XXL" => 0}
    sports_bra_sizes = {"XS" => 0, "S" => 0, "M" => 0, "L" => 0, "XL" => 0, "XXL" => 0}
    sports_jacket_sizes = {"XS" => 0, "S" => 0, "M" => 0, "L" => 0, "XL" => 0, "XXL" => 0}

    my_raw_sizes = RawSizeTotal.all
    my_raw_sizes.each do |myraw|
        puts myraw.inspect
        figure_my_size(tops_sizes, myraw, "tops")
        figure_my_size(leggings_sizes, myraw, "leggings")
        figure_my_size(sports_bra_sizes, myraw, "sports-bra")
        figure_my_size(sports_jacket_sizes, myraw, "sports-jacket")
    end
    


    puts "All done for NULL VALUES Subs!"
    puts "top sizes"
    puts tops_sizes.inspect
    puts "leggings sizes"
    puts leggings_sizes.inspect
    puts "sports bra sizes"
    puts sports_bra_sizes.inspect
    puts "sports-jacket sizes"
    puts sports_jacket_sizes.inspect

    size_file.write("NULLS (could include prepaid nulls) SIZES\n")
    size_file.write("Tops\n")
    size_file.write("XS,S,M,L,XL,XXL\n")
    size_array = ["XS", "S", "M", "L", "XL", "XXL"]
    size_array.each do |mys|
        if mys != "XXL"
            size_file.write("#{tops_sizes[mys]},")
        else
            size_file.write("#{tops_sizes[mys]}\n")
        end
    end
    size_file.write("Leggings\n")
    size_file.write("XS,S,M,L,XL,XXL\n")
    size_array.each do |mys|
        if mys != "XXL"
            size_file.write("#{leggings_sizes[mys]},")
        else
            size_file.write("#{leggings_sizes[mys]}\n")
        end
    end
    size_file.write("Sports Bra\n")
    size_file.write("XS,S,M,L,XL,XXL\n")
    size_array.each do |mys|
        if mys != "XXL"
            size_file.write("#{sports_bra_sizes[mys]},")
        else
            size_file.write("#{sports_bra_sizes[mys]}\n")
        end
    end
    size_file.write("Sports Jacket\n")
    size_file.write("XS,S,M,L,XL,XXL\n")
    size_array.each do |mys|
        if mys != "XXL"
            size_file.write("#{sports_jacket_sizes[mys]},")
        else
            size_file.write("#{sports_jacket_sizes[mys]}\n")
        end
    end

    #prepaid charging next month
    figure_prepaid_charging_next_month
    puts "Getting real size counts Prepaid Subs Charging Next Month"
    
    #start with tops
    tops_sizes = {"XS" => 0, "S" => 0, "M" => 0, "L" => 0, "XL" => 0, "XXL" => 0}
    leggings_sizes = {"XS" => 0, "S" => 0, "M" => 0, "L" => 0, "XL" => 0, "XXL" => 0}
    sports_bra_sizes = {"XS" => 0, "S" => 0, "M" => 0, "L" => 0, "XL" => 0, "XXL" => 0}
    sports_jacket_sizes = {"XS" => 0, "S" => 0, "M" => 0, "L" => 0, "XL" => 0, "XXL" => 0}

    my_raw_sizes = RawSizeTotal.all
    my_raw_sizes.each do |myraw|
        puts myraw.inspect
        figure_my_size(tops_sizes, myraw, "tops")
        figure_my_size(leggings_sizes, myraw, "leggings")
        figure_my_size(sports_bra_sizes, myraw, "sports-bra")
        figure_my_size(sports_jacket_sizes, myraw, "sports-jacket")
    end
    


    puts "All done for Prepaid Charging Next Month Subs!"
    puts "top sizes"
    puts tops_sizes.inspect
    puts "leggings sizes"
    puts leggings_sizes.inspect
    puts "sports bra sizes"
    puts sports_bra_sizes.inspect
    puts "sports-jacket sizes"
    puts sports_jacket_sizes.inspect

    size_file.write("Prepaid Charging Next Month Subs SIZES\n")
    size_file.write("Tops\n")
    size_file.write("XS,S,M,L,XL,XXK\n")
    size_array = ["XS", "S", "M", "L", "XL", "XXL"]
    size_array.each do |mys|
        if mys != "XXL"
            size_file.write("#{tops_sizes[mys]},")
        else
            size_file.write("#{tops_sizes[mys]}\n")
        end
    end
    size_file.write("Leggings\n")
    size_file.write("XS,S,M,L,XL,XXL\n")
    size_array.each do |mys|
        if mys != "XXL"
            size_file.write("#{leggings_sizes[mys]},")
        else
            size_file.write("#{leggings_sizes[mys]}\n")
        end
    end
    size_file.write("Sports Bra\n")
    size_file.write("XS,S,M,L,XL,XXL\n")
    size_array.each do |mys|
        if mys != "XXL"
            size_file.write("#{sports_bra_sizes[mys]},")
        else
            size_file.write("#{sports_bra_sizes[mys]}\n")
        end
    end
    size_file.write("Sports Jacket\n")
    size_file.write("XS,S,M,L,XL,XXL\n")
    size_array.each do |mys|
        if mys != "XXL"
            size_file.write("#{sports_jacket_sizes[mys]},")
        else
            size_file.write("#{sports_jacket_sizes[mys]}\n")
        end
    end   


        size_file.close
    end


    def setup_subscriptions_to_be_updated
        puts "Hi, setting up the subscriptions to be updated."
        puts "Deleting and resetting the table subscriptions_next_month_updated"
        SubscriptionsNextMonthUpdate.delete_all
        # Now reset index
        ActiveRecord::Base.connection.reset_pk_sequence!('subscriptions_next_month_updated')

        my_end_month = Date.today.end_of_month
        my_end_month_str = my_end_month.strftime("%Y-%m-%d")
        puts "End of the month = #{my_end_month_str}"
        my_start_month_plus = Date.today 
        my_start_month_plus = my_start_month_plus >> 1
        my_start_month_plus = my_start_month_plus.end_of_month + 1
        my_start_month_plus_str = my_start_month_plus.strftime("%Y-%m-%d")
        puts "my start_month_plus_str = #{my_start_month_plus_str}"
        
        #Allocate only month to month, no nulls
        #subs_update = "insert into subscriptions_next_month_updated (subscription_id, customer_id, updated_at, created_at, next_charge_scheduled_at, product_title, status, sku, shopify_product_id, shopify_variant_id, raw_line_items) select subscription_id, customer_id, updated_at, created_at, next_charge_scheduled_at, product_title, status, sku, shopify_product_id, shopify_variant_id, raw_line_item_properties from subscriptions where status = 'ACTIVE' and (next_charge_scheduled_at is not null and next_charge_scheduled_at > \'#{my_end_month_str}\' and next_charge_scheduled_at < \'#{my_start_month_plus_str}\')  and product_title not ilike \'3%month%\' and  created_at > \'2020-04-30\'"


        #subs_update = "insert into subscriptions_next_month_updated (subscription_id, customer_id, updated_at, created_at, next_charge_scheduled_at, product_title, status, sku, shopify_product_id, shopify_variant_id, raw_line_items) select subscription_id, customer_id, updated_at, created_at, next_charge_scheduled_at, product_title, status, sku, shopify_product_id, shopify_variant_id, raw_line_item_properties from subscriptions where status = 'ACTIVE' and (next_charge_scheduled_at is not null and next_charge_scheduled_at > '2020-07-31' and next_charge_scheduled_at < '2020-08-06')  and product_title  not ilike '3%month%' and product_title not ilike 'second%skin%' and product_title not ilike 'city%limit%' and product_title not ilike 'gear%up%' and product_title not ilike 'nightfall%' and product_title not ilike 'olive%grove%' and product_title not ilike 'a%new%gray%'"

        subs_update_xs = "insert into subscriptions_next_month_updated (subscription_id, customer_id, updated_at, created_at, next_charge_scheduled_at, product_title, status, sku, shopify_product_id, shopify_variant_id, raw_line_items) select subscriptions.subscription_id, subscriptions.customer_id, subscriptions.updated_at, subscriptions.created_at, subscriptions.next_charge_scheduled_at, subscriptions.product_title, subscriptions.status, subscriptions.sku, subscriptions.shopify_product_id, subscriptions.shopify_variant_id, subscriptions.raw_line_item_properties from subscriptions, sub_collection_sizes where subscriptions.status = 'ACTIVE' and subscriptions.next_charge_scheduled_at > '2021-04-02' and sub_collection_sizes.subscription_id = subscriptions.subscription_id and  subscriptions.next_charge_scheduled_at < '2021-05-01' and  subscriptions.product_title not ilike '3%month%'  and subscriptions.is_prepaid = \'f\' and ( sub_collection_sizes.product_collection not ilike 'spring%fling%' and sub_collection_sizes.product_collection not ilike 'after%storm%' ) and ( sub_collection_sizes.sports_bra = 'XS' or sub_collection_sizes.sports_jacket = 'XS' or sub_collection_sizes.leggings = 'XS' or sub_collection_sizes.tops = 'XS' or  sub_collection_sizes.sports_bra = 'XL' or sub_collection_sizes.sports_jacket = 'XL' or sub_collection_sizes.leggings = 'XL' or sub_collection_sizes.tops = 'XL' )"

        #subs_update_july_early = "insert into subscriptions_next_month_updated (subscription_id, customer_id, updated_at, created_at, next_charge_scheduled_at, product_title, status, sku, shopify_product_id, shopify_variant_id, raw_line_items) select subscriptions.subscription_id, subscriptions.customer_id, subscriptions.updated_at, subscriptions.created_at, subscriptions.next_charge_scheduled_at, subscriptions.product_title, subscriptions.status, subscriptions.sku, subscriptions.shopify_product_id, subscriptions.shopify_variant_id, subscriptions.raw_line_item_properties from subscriptions where subscriptions.status = 'ACTIVE' and subscriptions.next_charge_scheduled_at > '2020-06-30' and subscriptions.next_charge_scheduled_at < '2020-07-07'  and subscriptions.product_title not ilike \'3%month%\'  and subscriptions.product_title not ilike 'ooh%la%lavender%' and subscriptions.product_title not ilike 'pinky%swear%' and subscriptions.product_title not ilike 'berry%crush%' and subscriptions.product_title not ilike 'twilight%' and subscriptions.product_title not ilike 'moonlight%rose%' and subscriptions.product_title not ilike 'laguna%getaway%' and subscriptions.product_title not ilike 'wild%instinct%' and subscriptions.product_title not ilike 'summer%sunset' "

        delete_prepaid = "delete from subscriptions_next_month_updated where product_title ilike \'3 %month%\' "

        quick_estimation = "insert into subscriptions_next_month_updated (subscription_id, customer_id, updated_at, next_charge_scheduled_at, product_title, status, sku, shopify_product_id, shopify_variant_id, raw_line_items) select subscription_id, customer_id, updated_at, next_charge_scheduled_at, product_title, status, sku, shopify_product_id, shopify_variant_id, raw_line_item_properties from subscriptions where status = 'ACTIVE' and next_charge_scheduled_at is not null  "

        ActiveRecord::Base.connection.execute(subs_update_xs)
        ActiveRecord::Base.connection.execute(delete_prepaid)
        #ActiveRecord::Base.connection.execute(quick_estimation)
        puts "All done"


    end

    def load_customers_from_csv(myfile)

        CSV.foreach(myfile, :encoding => 'ISO8859-1:utf-8', :headers => true) do |row|
            puts row.inspect
            subscription_id = row['subscription_id']
            customer_id = row['customer_id']
            customer_email = row['customer_email']
            address_id = row['address_id']
            status = row['status']
            product_title = row['product_title']
            price = row['price']
            shopify_product_id = row['shopify_product_id']
            shopify_variant_id = row['shopify_variant_id']
            sku = row['sku']
            quantity = row['quantity']
            order_interval_unit = row['order_interval_unit']
            order_interval_frequency = row['order_interval_frequency']
            charge_interval_frequency = row['charge_interval_frequency']
            created_at = row['created_at']
            updated_at = row['updated_at']
            line_item_properties = row['properties']



            #<CSV::Row "subscription_id":"128354723" "customer_id":"58364767" "customer_email":"rdross302@gmail.com" "address_id":"62190597" "status":"ACTIVE" "product_title":"Midnight Sky - 3 Items" "variant_title":nil "recurring_price":"44.95" "price":"44.95" "quantity":"1" "shopify_product_id":"4601240649786" "shopify_variant_id":"32178527797306" "sku":"745934482897" "sku_override":nil "expire_after_specific_number_of_charges":nil "order_interval_frequency":"1" "charge_interval_frequency":"1" "order_interval_unit":"month" "charge_day_of_month":nil "charge_day_of_week":nil "properties":"[{\"name\": \"charge_interval_frequency\", \"value\": 1}, {\"name\": \"charge_interval_unit_type\", \"value\": \"Months\"}, {\"name\": \"leggings\", \"value\": \"XL\"}, {\"name\": \"main-product\", \"value\": \"true\"}, {\"name\": \"product_collection\", \"value\": \"Midnight Sky - 3 Items\"}, {\"name\": \"product_id\", \"value\": \"4601242091578\"}, {\"name\": \"shipping_interval_frequency\", \"value\": 1}, {\"name\": \"shipping_interval_unit_type\", \"value\": \"month\"}, {\"name\": \"sports-jacket\", \"value\": \"XL\"}, {\"name\": \"tops\", \"value\": \"XL\"}]" "cancelled_at":nil "cancellation_reason":nil "cancellation_reason_comments":nil "created_at":"2021-01-30 13:07:04" "deleted_at":nil "updated_at":"2021-01-30 13:07:04">

            puts line_item_properties

            break
        end

    end

    def setup_orders_to_be_updated
        puts "Hi setting up the orders to be updated for next month"
        OrdersNextMonthUpdate.delete_all
        ActiveRecord::Base.connection.reset_pk_sequence!('orders_next_month_updated')
        orders_update = "insert into orders_next_month_updated (order_id, transaction_id, charge_status, payment_processor, status, order_type, charge_id, address_id, shopify_order_id, shopify_order_number, shopify_cart_token, shipping_date, scheduled_at, shipped_date, processed_at, customer_id, first_name, last_name, is_prepaid, created_at, updated_at, email, line_items, total_price, shipping_address, billing_address, synced_at ) select order_id, transaction_id, charge_status, payment_processor, status, order_type, charge_id, address_id, shopify_order_id, shopify_order_number, shopify_cart_token, shipping_date, scheduled_at, shipped_date, processed_at, customer_id, first_name, last_name, is_prepaid, created_at, updated_at, email, line_items, total_price, shipping_address, billing_address, synced_at from orders where scheduled_at > '2019-01-22' and is_prepaid = 1 "
        ActiveRecord::Base.connection.execute(orders_update)
        puts "All done now!"


    end

    def load_allocation_collections
        AllocationCollection.delete_all
        ActiveRecord::Base.connection.reset_pk_sequence!('allocation_collections')
        CSV.foreach('allocation_collections_production.csv', :encoding => 'ISO8859-1:utf-8', :headers => true) do |row|
            puts row.inspect
            myallocation = AllocationCollection.create(collection_name: row['collection_name'], collection_id: row['collection_id'], collection_product_id: row['collection_product_id'])

        end
        puts "Done with loading allocation_collections table"
    end

    def load_allocation_matching_products
        AllocationMatchingProduct.delete_all
        ActiveRecord::Base.connection.reset_pk_sequence!('allocation_matching_products')
        CSV.foreach('allocation_matching_products_production.csv', :encoding => 'ISO8859-1:utf-8', :headers => true) do |row|
            puts row.inspect
            my_matching = AllocationMatchingProduct.create(product_title: row['product_title'], incoming_product_id: row['incoming_product_id'], prod_type: row['prod_type'], outgoing_product_id: row['outgoing_product_id'])

        end
        puts "Done with loading allocation_matching_products table"

    end

    def load_allocation_alternate_products
        AllocationAlternateProduct.delete_all
        ActiveRecord::Base.connection.reset_pk_sequence!('allocation_alternate_products')
        CSV.foreach('allocation_alternate_products_production.csv', :encoding => 'ISO8859-1:utf-8', :headers => true) do |row|
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

    def reset_sub_dry_run
        SubNextMonthDryRun.delete_all
        ActiveRecord::Base.connection.reset_pk_sequence!('subs_next_month_dry_run')
    end

    def allocation_switchable_products_helper(myfile)
        myoutfile = "new_#{myfile}"
        File.delete(myoutfile) if File.exist?(myoutfile)
        product_array = []
        column_header = ["product_title", "shopify_product_id", "prod_type"]
        CSV.foreach(myfile, :encoding => 'ISO8859-1:utf-8', :headers => true) do |row|
            puts row.inspect
            temp_hash = {"product_title" => row['product_title'], "shopify_product_id" => row['shopify_product_id']}
            product_array << temp_hash

        end
        CSV.open(myoutfile,'a+', :write_headers=> true, :headers => column_header) do |hdr|
            column_header = nil
            product_array.each do |myp|
                product_type = 99
                case myp["product_title"]
                when /3\sitem/i
                    product_type = 3
                when /5\sitem/i
                    product_type = 5
                when /2\sitem/i
                    product_type = 2
                else
                    product_type = 555
                end
                csv_data_out = [myp["product_title"], myp["shopify_product_id"], product_type]
                hdr << csv_data_out
            end
        end

    end

    def load_allocation_switchable_products_table
        AllocationSwitchableProduct.delete_all
        ActiveRecord::Base.connection.reset_pk_sequence!('allocation_switchable_products')
        CSV.foreach('allocation_switchable_products_production.csv', :encoding => 'ISO8859-1:utf-8', :headers => true) do |row|
            puts row.inspect
            myswitchable = AllocationSwitchableProduct.create(product_title: row['product_title'], shopify_product_id: row['shopify_product_id'], prod_type: row['prod_type'], prepaid: row['prepaid'])

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
        params = {"action" => "allocating subscriptions for next month", "recharge_change_header" => @my_change_header}
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

    def background_allocate_orders
        params = {"action" => "allocating orders for next month", "recharge_change_header" => @my_change_header}
        Resque.enqueue(BackgroundOrderAllocate, params)


    end

    class BackgroundOrderAllocate
        extend BackgroundOrderHelper
        @queue = "background_order_allocation"
        def self.perform(params)
            background_allocate_orders(params)
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