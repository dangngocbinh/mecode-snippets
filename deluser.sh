#!/bin/bash

# Kiểm tra xem WP-CLI đã được cài đặt chưa
if ! command -v wp &> /dev/null; then
    echo "WP-CLI chưa được cài đặt. Vui lòng cài đặt nó trước."
    exit 1
fi

# Kiểm tra xem người dùng adminpro và hoa100ty2004 có tồn tại không
if ! wp user get adminpro &> /dev/null; then
    echo "Người dùng adminpro không tồn tại. Vui lòng kiểm tra lại."
    exit 1
fi

if ! wp user get hoa100ty2004 &> /dev/null; then
    echo "Người dùng hoa100ty2004 không tồn tại. Vui lòng kiểm tra lại."
    exit 1
fi

# Lấy ID của người dùng adminpro và hoa100ty2004
admin_id=$(wp user get adminpro --field=ID)
hoa_id=$(wp user get hoa100ty2004 --field=ID)

# Lấy danh sách tất cả người dùng trừ adminpro và hoa100ty2004
users_to_delete=$(wp user list --field=ID --exclude=$admin_id,$hoa_id)

# Kiểm tra xem có người dùng nào để xóa không
if [ -z "$users_to_delete" ]; then
    echo "Không có người dùng nào để xóa."
    exit 0
fi

# Hiển thị số lượng người dùng sẽ bị xóa
user_count=$(echo $users_to_delete | wc -w)
echo "Có $user_count người dùng sẽ bị xóa."

# Xác nhận trước khi xóa
read -p "Bạn có chắc chắn muốn xóa tất cả những người dùng này? (y/n): " confirm
if [ "$confirm" != "y" ]; then
    echo "Hủy bỏ thao tác."
    exit 0
fi

# Xóa người dùng
for user_id in $users_to_delete; do
    if wp user delete $user_id --reassign=$admin_id; then
        echo "Đã xóa người dùng có ID $user_id"
    else
        echo "Không thể xóa người dùng có ID $user_id"
    fi
done

echo "Đã hoàn tất việc xóa người dùng."
