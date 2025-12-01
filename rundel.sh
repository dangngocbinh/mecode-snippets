#!/bin/bash

# Function to check if WP-CLI is installed
check_wp_cli() {
    if ! command -v wp &> /dev/null; then
        echo "WP-CLI is not installed. Please install it first."
        exit 1
    fi
}

# Function to delete orders
delete_orders() {
    local batch_size=$1
    local wp_user=$2
    local total_deleted=0

    while true; do
        # Get order IDs
        order_ids=$(wp wc shop_order list --format=ids  --user=$wp_user)

        # Check if there are no more orders
        if [ -z "$order_ids" ]; then
            echo "No more orders to delete."
            break
        fi

        # Count the number of orders in this batch
        order_count=$(echo $order_ids | wc -w)

        echo "Found $order_count orders to delete."
#        read -p "Do you want to delete these orders? (y/n): " confirm
	confirm="y"
        if [ "$confirm" = "y" ]; then
            # Delete orders using a for loop
            for id in $order_ids; do
                wp wc shop_order delete $id --force=1 --user=$wp_user
                if [ $? -eq 0 ]; then
                    total_deleted=$((total_deleted + 1))
                    echo "Deleted order $id"
                else
                    echo "Failed to delete order $id"
                fi
            done

            echo "Deleted $total_deleted orders in this batch. Total deleted: $total_deleted"
        else
            echo "Skipping this batch."
        fi

#        read -p "Continue to the next batch? (y/n): " continue
#       if [ "$continue" != "y" ]; then
 #          break
  #     fi
    done

    echo "Total orders deleted: $total_deleted"
}

# Main script
check_wp_cli

# Get WordPress user
read -p "Enter WordPress user with permissions to delete orders: " wp_user

# Get batch size
read -p "Enter batch size (default 100): " batch_size
batch_size=${batch_size:-100}

# Run the delete function
delete_orders $batch_size $wp_user
