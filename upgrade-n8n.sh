#!/bin/bash

# Kiểm tra quyền root
if [ "$EUID" -ne 0 ]; then 
  echo "Script này cần được chạy với quyền root"
  exit 1
fi

# Đường dẫn thư mục n8n
N8N_DIR="/home/n8n"
BACKUP_DIR="/root/backup-n8n"

# Hiển thị cảnh báo
echo "=== CẢNH BÁO ==="
echo "Việc nâng cấp n8n có thể ảnh hưởng đến dữ liệu."
echo "Bạn nên backup dữ liệu trước khi tiếp tục."
echo "================="

# Hỏi người dùng có muốn backup
read -p "Bạn có muốn backup dữ liệu n8n không? (y/n): " answer

if [[ $answer == [yY] || $answer == [yY][eE][sS] ]]; then
    echo "Bắt đầu quá trình backup..."
    
    # Di chuyển đến thư mục n8n
    cd "$N8N_DIR"
    
    # Dừng n8n trước khi backup
    echo "Dừng n8n để backup an toàn..."
    docker-compose down
    
    if [ $? -eq 0 ]; then
        echo "Đã dừng n8n thành công"
    else
        echo "Lỗi khi dừng n8n! Kiểm tra lại."
        exit 1
    fi
    
    # Tạo thư mục backup nếu chưa tồn tại
    mkdir -p "$BACKUP_DIR"
    
    # Tạo backup với timestamp
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_PATH="$BACKUP_DIR/n8n_backup_$TIMESTAMP"
    
    echo "Đang backup dữ liệu..."
    rsync -av "$N8N_DIR/" "$BACKUP_PATH/"
    
    if [ $? -eq 0 ]; then
        echo "Backup hoàn tất tại $BACKUP_PATH"
    else
        echo "Lỗi khi backup! Hủy quá trình nâng cấp."
        exit 1
    fi
    
else
    read -p "Bạn có chắc chắn muốn tiếp tục mà không backup? (y/n): " confirm
    if [[ $confirm != [yY] && $confirm != [yY][eE][sS] ]]; then
        echo "Hủy quá trình nâng cấp."
        exit 1
    fi
    
    # Nếu không backup, vẫn cần dừng n8n trước khi nâng cấp
    echo "Dừng n8n để chuẩn bị nâng cấp..."
    cd "$N8N_DIR"
    docker-compose down
fi

# Bắt đầu quá trình nâng cấp
echo "Bắt đầu nâng cấp n8n..."

# Pull image mới nhất
echo "Tải image n8n mới nhất..."
docker-compose pull

if [ $? -eq 0 ]; then
    echo "Đã tải image mới thành công"
else
    echo "Lỗi khi tải image mới!"
    exit 1
fi

# Khởi động container với image mới
echo "Khởi động n8n với phiên bản mới..."
docker-compose up -d

if [ $? -eq 0 ]; then
    echo "Đã khởi động n8n thành công"
else
    echo "Lỗi khi khởi động n8n!"
    exit 1
fi

# Kiểm tra trạng thái
echo "Đợi 15 giây để n8n khởi động hoàn toàn..."
sleep 15

echo "Kiểm tra trạng thái container..."
if docker-compose ps | grep -q "Up"; then
    echo "✅ Nâng cấp n8n thành công!"
    echo ""
    echo "=== THÔNG TIN PHIÊN BẢN ==="
    docker-compose exec n8n n8n --version 2>/dev/null || echo "Không thể lấy thông tin phiên bản"
    echo ""
    echo "=== TRẠNG THÁI CONTAINER ==="
    docker-compose ps
else
    echo "❌ Có lỗi xảy ra! Container không hoạt động."
    echo ""
    echo "=== LOGS CONTAINER ==="
    docker-compose logs --tail=50
    echo ""
    echo "=== HƯỚNG DẪN KHÔI PHỤC ==="
    if [[ $answer == [yY] || $answer == [yY][eE][sS] ]]; then
        echo "Bạn có thể khôi phục từ backup tại: $BACKUP_PATH"
        echo "Chạy lệnh: rsync -av $BACKUP_PATH/ $N8N_DIR/"
    fi
fi

echo ""
echo "=== HOÀN TẤT QUÁ TRÌNH NÂNG CẤP ==="
