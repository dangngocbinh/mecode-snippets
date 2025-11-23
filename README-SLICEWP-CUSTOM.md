# SliceWP Custom Affiliate Registration

Plugin tùy chỉnh cho SliceWP để:
- ✅ Không bắt buộc nhập email khi đăng ký affiliate
- ✅ Không bắt buộc nhập "How to promote us"
- ✅ Thêm trường **Thông tin tài khoản nhận tiền** (bắt buộc)
- ✅ Cho phép affiliate cập nhật thông tin tài khoản trong dashboard

## Cài đặt

### Cách 1: Upload như một plugin

1. Upload thư mục chứa file `slicewp-custom-affiliate-registration.php` vào `/wp-content/plugins/`
2. Vào WordPress Admin > Plugins
3. Kích hoạt plugin "SliceWP Custom Affiliate Registration"

### Cách 2: Thêm vào functions.php

Copy toàn bộ code từ file `slicewp-custom-affiliate-registration.php` (bỏ qua phần header plugin) và paste vào file `functions.php` của theme.

## Tính năng

### 1. Email không bắt buộc
- Khi đăng ký, affiliate có thể bỏ trống email
- Hệ thống tự tạo email giả để bypass validation

### 2. Trường thông tin tài khoản nhận tiền
- Hiển thị trong form đăng ký affiliate
- **Bắt buộc phải nhập**
- Có thể nhập: số tài khoản ngân hàng, Momo, ZaloPay, v.v.

### 3. Cập nhật thông tin tài khoản
- Affiliate có thể cập nhật thông tin tài khoản trong dashboard
- Hiển thị ở đầu trang dashboard affiliate

### 4. Quản lý từ Admin
- Admin có thể xem thông tin tài khoản của affiliate
- Thêm cột "Tài khoản nhận tiền" trong danh sách affiliates
- Có thể chỉnh sửa từ trang edit affiliate

## Hooks và Filters được sử dụng

```php
// Validation
slicewp_validate_affiliate_registration_data

// Form fields
slicewp_form_affiliate_registration
slicewp_affiliate_registration_form_fields

// Lưu dữ liệu
slicewp_insert_affiliate
slicewp_update_affiliate

// Hiển thị trong dashboard
slicewp_affiliate_account_top

// Admin columns
slicewp_list_table_get_columns_affiliates
slicewp_list_table_get_column_value_affiliates

// Admin edit page
slicewp_view_affiliates_edit_after_status
```

## Tùy chỉnh

### Thay đổi label của trường
Sửa trong function `custom_add_payment_account_field()`:

```php
<?php echo __( 'Thông tin tài khoản nhận tiền', 'slicewp' ); ?>
```

### Thêm validation phức tạp hơn
Sửa trong function `custom_validate_payment_account()` để thêm validation cho format số tài khoản, v.v.

## Yêu cầu
- WordPress 5.0+
- SliceWP plugin đã được cài đặt và kích hoạt

## Lưu ý
- Backup website trước khi cài đặt
- Test trên môi trường staging trước
- Code tương thích với SliceWP free version

## Hỗ trợ
Nếu cần tùy chỉnh thêm, có thể chỉnh sửa trực tiếp trong file PHP.
