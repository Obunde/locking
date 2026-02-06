namespace :concurrency do
  desc "Test pessimistic locking with concurrent order updates"
  task test_order_locking: :environment do
    puts "========================================="
    puts "Testing Pessimistic Locking with Concurrent Order Updates"
    puts "========================================="
    
    # Setup: Create test data
    puts "\n1. Setting up test data..."
    
    # Clean up existing test data
    test_users = User.where(email: ['test_user1@example.com', 'test_user2@example.com'])
    test_orders = Order.where(user_id: test_users.pluck(:id))
    OrderedList.where(order_id: test_orders.pluck(:id)).destroy_all
    test_orders.destroy_all
    test_users.destroy_all
    Item.where(name: 'Test Concurrency Item').destroy_all
    
    # Create users
    user1 = User.create!(
      name: "Test User 1",
      email: "test_user1@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    
    user2 = User.create!(
      name: "Test User 2",
      email: "test_user2@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    
    # Create an item with initial quantity
    item = Item.create!(
      name: "Test Concurrency Item",
      total_quantity: 0
    )
    
    puts "   ✓ Created users: #{user1.email}, #{user2.email}"
    puts "   ✓ Created item: #{item.name} (initial quantity: #{item.total_quantity})"
    
    # Test: Simulate concurrent updates
    puts "\n2. Simulating concurrent order creation..."
    puts "   Each user will create an order for 10 units"
    puts "   Expected final quantity: 20"
    
    initial_quantity = item.total_quantity
    
    threads = []
    results = []
    
    # Thread 1: User 1 creates an order
    threads << Thread.new do
      begin
        ActiveRecord::Base.connection_pool.with_connection do
          order1 = user1.orders.create!
          ordered_list1 = order1.ordered_lists.create!(item_id: item.id, quantity: 10)
          
          puts "   [Thread 1] Order created for User 1"
          
          # Add a small delay to increase chance of race condition
          sleep(0.1)
          
          order1.update_total_quantity
          
          puts "   [Thread 1] Updated item quantity"
          results << { thread: 1, success: true }
        end
      rescue => e
        puts "   [Thread 1] Error: #{e.message}"
        results << { thread: 1, success: false, error: e.message }
      end
    end
    
    # Thread 2: User 2 creates an order (starts almost simultaneously)
    threads << Thread.new do
      begin
        ActiveRecord::Base.connection_pool.with_connection do
          order2 = user2.orders.create!
          ordered_list2 = order2.ordered_lists.create!(item_id: item.id, quantity: 10)
          
          puts "   [Thread 2] Order created for User 2"
          
          # Add a small delay to increase chance of race condition
          sleep(0.1)
          
          order2.update_total_quantity
          
          puts "   [Thread 2] Updated item quantity"
          results << { thread: 2, success: true }
        end
      rescue => e
        puts "   [Thread 2] Error: #{e.message}"
        results << { thread: 2, success: false, error: e.message }
      end
    end
    
    # Wait for both threads to complete
    threads.each(&:join)
    
    # Verify results
    puts "\n3. Verifying results..."
    item.reload
    final_quantity = item.total_quantity
    expected_quantity = initial_quantity + 20
    
    puts "   Initial quantity: #{initial_quantity}"
    puts "   Final quantity: #{final_quantity}"
    puts "   Expected quantity: #{expected_quantity}"
    
    if final_quantity == expected_quantity
      puts "\n✅ SUCCESS: Pessimistic locking worked correctly!"
      puts "   Both updates were applied sequentially without race conditions."
    else
      puts "\n❌ FAILURE: Race condition detected!"
      puts "   The pessimistic lock may not be working properly."
      puts "   Lost updates: #{expected_quantity - final_quantity}"
    end
    
    # Display thread results
    puts "\n4. Thread execution summary:"
    results.each do |result|
      if result[:success]
        puts "   ✓ Thread #{result[:thread]}: Completed successfully"
      else
        puts "   ✗ Thread #{result[:thread]}: Failed - #{result[:error]}"
      end
    end
    
    puts "\n========================================="
    puts "Test completed"
    puts "========================================="
    
    # Cleanup
    puts "\n5. Cleaning up test data..."
    test_orders = Order.where(user_id: [user1.id, user2.id])
    OrderedList.where(order_id: test_orders.pluck(:id)).destroy_all
    test_orders.destroy_all
    user1.destroy
    user2.destroy
    item.destroy
    puts "   ✓ Test data cleaned up"
  end
  
  desc "Test race condition WITHOUT pessimistic locking (demonstrates the problem)"
  task test_without_locking: :environment do
    puts "========================================="
    puts "Testing WITHOUT Pessimistic Locking (Demonstrating Race Condition)"
    puts "========================================="
    
    # Setup: Create test data
    puts "\n1. Setting up test data..."
    
    # Clean up existing test data
    race_users = User.where(email: ['race_user1@example.com', 'race_user2@example.com'])
    race_orders = Order.where(user_id: race_users.pluck(:id))
    OrderedList.where(order_id: race_orders.pluck(:id)).destroy_all
    race_orders.destroy_all
    race_users.destroy_all
    Item.where(name: 'Race Condition Test Item').destroy_all
    
    # Create users
    user1 = User.create!(
      name: "Race User 1",
      email: "race_user1@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    
    user2 = User.create!(
      name: "Race User 2",
      email: "race_user2@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    
    # Create an item with initial quantity
    item = Item.create!(
      name: "Race Condition Test Item",
      total_quantity: 0
    )
    
    puts "   ✓ Created users: #{user1.email}, #{user2.email}"
    puts "   ✓ Created item: #{item.name} (initial quantity: #{item.total_quantity})"
    
    # Test: Simulate concurrent updates WITHOUT locking
    puts "\n2. Simulating concurrent updates WITHOUT pessimistic locking..."
    puts "   Each thread will increment quantity by 10"
    puts "   Expected final quantity: 20"
    puts "   Note: This may produce incorrect results due to race conditions!"
    
    initial_quantity = item.total_quantity
    
    threads = []
    
    # Thread 1
    threads << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        current_item = Item.find(item.id)
        current_quantity = current_item.total_quantity
        
        # Simulate processing time
        sleep(0.05)
        
        current_item.update!(total_quantity: current_quantity + 10)
        puts "   [Thread 1] Updated quantity to #{current_item.total_quantity}"
      end
    end
    
    # Thread 2
    threads << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        current_item = Item.find(item.id)
        current_quantity = current_item.total_quantity
        
        # Simulate processing time
        sleep(0.05)
        
        current_item.update!(total_quantity: current_quantity + 10)
        puts "   [Thread 2] Updated quantity to #{current_item.total_quantity}"
      end
    end
    
    # Wait for both threads to complete
    threads.each(&:join)
    
    # Verify results
    puts "\n3. Verifying results..."
    item.reload
    final_quantity = item.total_quantity
    expected_quantity = initial_quantity + 20
    
    puts "   Initial quantity: #{initial_quantity}"
    puts "   Final quantity: #{final_quantity}"
    puts "   Expected quantity: #{expected_quantity}"
    
    if final_quantity == expected_quantity
      puts "\n⚠️  No race condition occurred this time (lucky!)"
      puts "   But without locking, race conditions can happen unpredictably."
    else
      puts "\n❌ RACE CONDITION DETECTED!"
      puts "   Lost updates: #{expected_quantity - final_quantity}"
      puts "   This demonstrates why pessimistic locking is necessary!"
    end
    
    puts "\n========================================="
    puts "Test completed"
    puts "========================================="
    
    # Cleanup
    puts "\n4. Cleaning up test data..."
    race_orders = Order.where(user_id: [user1.id, user2.id])
    OrderedList.where(order_id: race_orders.pluck(:id)).destroy_all
    race_orders.destroy_all
    user1.destroy
    user2.destroy
    item.destroy
    puts "   ✓ Test data cleaned up"
  end
end
