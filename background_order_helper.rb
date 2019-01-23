#background_order_helper.rb

require 'dotenv'
require 'active_support/core_ext'
require 'sinatra/activerecord'
require 'httparty'
require_relative 'models/model'


Dotenv.load

module BackgroundOrderHelper

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



    def allocate_orders(recharge_change_header)
        puts "Starting allocation"
        my_now = Time.now
        my_size_hash = Hash.new
        myorders = OrdersNextMonthUpdate.where("updated = ? and bad_order = ?", false, false)
        myorders.each do |myord|
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
                #allocate_single_subscription(my_index, my_size_hash, sub, "sports-jacket",recharge_change_header )
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