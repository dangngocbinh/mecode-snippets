<?php
/**
 * Plugin Name: SliceWP Custom Affiliate Registration
 * Description: Tùy chỉnh form đăng ký affiliate SliceWP - Email và How to Promo không bắt buộc, thêm trường thông tin tài khoản nhận tiền
 * Version: 1.0.0
 * Author: Custom Code
 */

// Ngăn truy cập trực tiếp
if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

/**
 * 1. Làm cho trường Email không bắt buộc trong form đăng ký
 */
add_filter( 'slicewp_validate_affiliate_registration_data', 'custom_slicewp_make_email_optional', 10, 2 );
function custom_slicewp_make_email_optional( $validation, $data ) {
    // Nếu email trống, bỏ qua validation lỗi email
    if ( empty( $data['user_email'] ) ) {
        // Tạo email giả để bypass validation
        $data['user_email'] = 'affiliate_' . time() . '@noemail.local';
        $_POST['user_email'] = $data['user_email'];
    }

    return $validation;
}

/**
 * 2. Thêm trường thông tin tài khoản nhận tiền vào form đăng ký
 */
add_action( 'slicewp_form_affiliate_registration', 'custom_add_payment_account_field', 10 );
function custom_add_payment_account_field() {
    ?>
    <div class="slicewp-field-wrapper slicewp-field-wrapper-inline">
        <label for="slicewp-payment-account">
            <?php echo __( 'Thông tin tài khoản nhận tiền', 'slicewp' ); ?> *
            <span class="slicewp-field-required">*</span>
        </label>
        <input id="slicewp-payment-account" name="payment_account_info" type="text" value="<?php echo ( ! empty( $_POST['payment_account_info'] ) ? esc_attr( $_POST['payment_account_info'] ) : '' ); ?>" />
        <p class="slicewp-field-description">
            <?php echo __( 'Nhập số tài khoản ngân hàng hoặc thông tin ví điện tử (VD: Momo, ZaloPay, Bank Account)', 'slicewp' ); ?>
        </p>
    </div>
    <?php
}

/**
 * 3. Validate trường thông tin tài khoản (bắt buộc nhập)
 */
add_filter( 'slicewp_validate_affiliate_registration_data', 'custom_validate_payment_account', 20, 2 );
function custom_validate_payment_account( $validation, $data ) {
    if ( empty( $_POST['payment_account_info'] ) ) {
        $validation[] = __( 'Vui lòng nhập thông tin tài khoản nhận tiền.', 'slicewp' );
    }

    return $validation;
}

/**
 * 4. Lưu thông tin tài khoản nhận tiền khi đăng ký
 */
add_action( 'slicewp_insert_affiliate', 'custom_save_payment_account', 10, 1 );
function custom_save_payment_account( $affiliate_id ) {
    if ( ! empty( $_POST['payment_account_info'] ) ) {
        slicewp_update_affiliate_meta( $affiliate_id, 'payment_account_info', sanitize_text_field( $_POST['payment_account_info'] ) );
    }
}

/**
 * 5. Hiển thị trường thông tin tài khoản trong dashboard của affiliate
 */
add_action( 'slicewp_affiliate_account_top', 'custom_display_payment_account_section' );
function custom_display_payment_account_section() {
    $affiliate = slicewp_get_current_affiliate();

    if ( ! $affiliate ) {
        return;
    }

    $payment_account_info = slicewp_get_affiliate_meta( $affiliate->get('id'), 'payment_account_info', true );

    // Xử lý cập nhật thông tin
    if ( isset( $_POST['update_payment_account'] ) && check_admin_referer( 'slicewp_update_payment_account', 'slicewp_token' ) ) {
        $new_payment_info = sanitize_text_field( $_POST['payment_account_info'] );
        slicewp_update_affiliate_meta( $affiliate->get('id'), 'payment_account_info', $new_payment_info );
        $payment_account_info = $new_payment_info;
        echo '<div class="slicewp-message slicewp-message-success">' . __( 'Thông tin tài khoản đã được cập nhật thành công!', 'slicewp' ) . '</div>';
    }

    ?>
    <div class="slicewp-card slicewp-card-payment-account" style="margin-bottom: 30px;">
        <div class="slicewp-card-header">
            <h3><?php echo __( 'Thông tin tài khoản nhận tiền', 'slicewp' ); ?></h3>
        </div>
        <div class="slicewp-card-inner">
            <form method="post" action="">
                <?php wp_nonce_field( 'slicewp_update_payment_account', 'slicewp_token' ); ?>

                <div class="slicewp-field-wrapper">
                    <label for="payment-account-info">
                        <?php echo __( 'Số tài khoản / Ví điện tử', 'slicewp' ); ?>
                    </label>
                    <input type="text" id="payment-account-info" name="payment_account_info" value="<?php echo esc_attr( $payment_account_info ); ?>" class="slicewp-field" style="width: 100%; max-width: 500px;" />
                    <p class="slicewp-field-description">
                        <?php echo __( 'Nhập số tài khoản ngân hàng, Momo, ZaloPay hoặc thông tin ví khác để nhận thanh toán hoa hồng.', 'slicewp' ); ?>
                    </p>
                </div>

                <button type="submit" name="update_payment_account" class="slicewp-button-primary">
                    <?php echo __( 'Cập nhật thông tin', 'slicewp' ); ?>
                </button>
            </form>
        </div>
    </div>
    <?php
}

/**
 * 6. Xóa yêu cầu bắt buộc cho trường "How did you hear about us" (nếu có)
 */
add_filter( 'slicewp_affiliate_registration_form_fields', 'custom_make_promo_field_optional', 10, 1 );
function custom_make_promo_field_optional( $fields ) {
    // Tìm và làm cho trường promotional không bắt buộc
    foreach ( $fields as $key => $field ) {
        if ( isset( $field['name'] ) && in_array( $field['name'], array( 'promotional_method', 'website', 'how_promote' ) ) ) {
            $fields[$key]['required'] = false;
        }
    }

    return $fields;
}

/**
 * 7. Thêm cột thông tin tài khoản vào danh sách affiliate trong admin (optional)
 */
add_filter( 'slicewp_list_table_get_columns_affiliates', 'custom_add_payment_account_column' );
function custom_add_payment_account_column( $columns ) {
    $columns['payment_account'] = __( 'Tài khoản nhận tiền', 'slicewp' );
    return $columns;
}

add_filter( 'slicewp_list_table_get_column_value_affiliates', 'custom_payment_account_column_value', 10, 3 );
function custom_payment_account_column_value( $value, $column_name, $item ) {
    if ( $column_name == 'payment_account' ) {
        $payment_info = slicewp_get_affiliate_meta( $item->get('id'), 'payment_account_info', true );
        $value = ! empty( $payment_info ) ? esc_html( $payment_info ) : '-';
    }

    return $value;
}

/**
 * 8. Hiển thị thông tin tài khoản trong trang chi tiết affiliate (admin)
 */
add_action( 'slicewp_view_affiliates_edit_after_status', 'custom_admin_display_payment_account' );
function custom_admin_display_payment_account( $affiliate ) {
    $payment_account_info = slicewp_get_affiliate_meta( $affiliate->get('id'), 'payment_account_info', true );
    ?>
    <div class="slicewp-card">
        <div class="slicewp-card-header">
            <?php echo __( 'Thông tin tài khoản nhận tiền', 'slicewp' ); ?>
        </div>
        <div class="slicewp-card-inner">
            <div class="slicewp-field-wrapper slicewp-field-wrapper-inline">
                <label for="slicewp-payment-account-admin">
                    <?php echo __( 'Tài khoản nhận tiền', 'slicewp' ); ?>
                </label>
                <input id="slicewp-payment-account-admin" name="payment_account_info" type="text" value="<?php echo esc_attr( $payment_account_info ); ?>" />
            </div>
        </div>
    </div>
    <?php
}

/**
 * 9. Lưu thông tin tài khoản khi admin cập nhật từ backend
 */
add_action( 'slicewp_update_affiliate', 'custom_admin_save_payment_account', 10, 2 );
function custom_admin_save_payment_account( $affiliate_id, $data ) {
    if ( isset( $_POST['payment_account_info'] ) ) {
        slicewp_update_affiliate_meta( $affiliate_id, 'payment_account_info', sanitize_text_field( $_POST['payment_account_info'] ) );
    }
}
