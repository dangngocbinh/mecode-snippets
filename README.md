# Docker Volume Migration Tools

Công cụ backup và restore Docker volumes giữa các VPS hoặc lưu thành file để backup.

## Tính năng

### Backup Script (`docker-volume-backup.sh`)
- Chọn một hoặc nhiều Docker volumes để backup
- Xuất ra file `.tar.gz` (bao gồm cả metadata)
- Đồng bộ trực tiếp sang VPS khác qua SSH
- Menu interactive dễ sử dụng với `fzf`:
  - Dùng phím mũi tên để di chuyển
  - TAB để chọn/bỏ chọn volumes
  - Gõ text để search/filter
  - ESC để chọn tất cả
  - Fallback về menu số nếu không có fzf

### Restore Script (`docker-volume-restore.sh`)
- Khôi phục từ file backup `.tar.gz`
- Khôi phục từ VPS từ xa
- Tự động tạo volume mới hoặc ghi đè volume cũ
- Cho phép đổi tên volume khi restore
- Menu interactive với `fzf` (tương tự backup script)

## Yêu cầu

- Docker đã cài đặt và đang chạy
- SSH access đến VPS đích (nếu sync qua VPS)
- Quyền thực thi script (đã được set)
- `fzf` (optional, recommended) - Sẽ tự động cài nếu chưa có
  - macOS: `brew install fzf`
  - Ubuntu/Debian: `apt install fzf`
  - CentOS/RHEL: `yum install fzf`

## Cách sử dụng

### 1. Backup volumes

```bash
./docker-volume-backup.sh
```

**Các bước:**
1. Script sẽ hiển thị danh sách volumes
2. Chọn volumes bằng cách nhập số (VD: `1,3,5` hoặc `0` để chọn tất cả)
3. Chọn đích đến:
   - **Option 1**: Export ra file tar.gz
     - Nhập đường dẫn thư mục lưu file (mặc định: `./backups`)
   - **Option 2**: Sync sang VPS khác
     - Nhập thông tin VPS: `user@ip`, port SSH, đường dẫn remote

**Ví dụ:**

```
Available Docker volumes:

  0) [Select ALL volumes]
  1) mysql_data
  2) postgres_data
  3) redis_data

Enter volume numbers (comma-separated, e.g., 1,3,5) or 0 for all:
> 1,2

Select backup destination:
  1) Export to local file (tar.gz)
  2) Sync to remote VPS (rsync)

Enter choice (1 or 2): 1
Enter output directory [default: ./backups]: /tmp/my-backups
```

### 2. Restore volumes

```bash
./docker-volume-restore.sh
```

**Các bước:**
1. Chọn nguồn restore:
   - **Option 1**: Từ file backup local
     - Nhập đường dẫn thư mục chứa backup
     - Chọn file backup cần restore
     - Có thể đổi tên volume khi restore
   - **Option 2**: Từ VPS từ xa
     - Nhập thông tin VPS
     - Chọn volumes từ remote

**Ví dụ:**

```
Select restore source:
  1) Restore from local backup files (tar.gz)
  2) Restore from remote VPS

Enter choice (1 or 2): 1
Enter backup directory [default: ./backups]: /tmp/my-backups

Available backup files:

  0) [Restore ALL backups]
  1) mysql_data_20231201_143022.tar.gz (125M)
  2) postgres_data_20231201_143045.tar.gz (89M)

Enter backup numbers (comma-separated) or 0 for all:
> 1

Target volume name: mysql_data
Press Enter to use this name, or type a new name: mysql_data_restored
```

## Cấu trúc file backup

Mỗi file backup (`.tar.gz`) chứa:
- Toàn bộ dữ liệu của volume
- Metadata của volume (thông tin cấu hình, labels, etc.)

Format tên file: `{volume_name}_{YYYYMMDD}_{HHMMSS}.tar.gz`

## Lưu ý

### Backup
- Volume đang được sử dụng vẫn có thể backup (read-only mode)
- Script tự động tạo thư mục backup nếu chưa tồn tại
- Khi sync sang VPS, cần đảm bảo SSH connection hoạt động

### Restore
- Nếu volume đã tồn tại, script sẽ hỏi có muốn ghi đè không
- Có thể restore với tên volume khác với tên gốc
- Volume đang được container sử dụng không thể xóa/ghi đè

### SSH/VPS
- Cần setup SSH key hoặc nhập password khi connect
- Port mặc định: 22
- Đường dẫn remote mặc định: `/tmp/docker-volumes`

## Troubleshooting

**Lỗi: "Docker is not running"**
- Kiểm tra Docker daemon: `docker info`
- Kiểm tra quyền user: thêm user vào group docker

**Lỗi: "Cannot connect to remote host"**
- Kiểm tra SSH: `ssh -p {port} {user}@{host}`
- Kiểm tra firewall/security group

**Lỗi: "Cannot remove volume (may be in use)"**
- Stop các container đang dùng volume: `docker ps | grep {volume}`
- Dùng: `docker stop {container_id}`

## Examples

### Backup tất cả volumes ra file
```bash
./docker-volume-backup.sh
# Chọn 0 (all volumes)
# Chọn 1 (export to file)
# Nhập đường dẫn: ./backups
```

### Sync một volume sang VPS khác
```bash
./docker-volume-backup.sh
# Chọn volume cụ thể (VD: 1)
# Chọn 2 (sync to VPS)
# Nhập: root@192.168.1.100
# Port: 22
# Path: /backup/docker-volumes
```

### Restore từ backup và đổi tên
```bash
./docker-volume-restore.sh
# Chọn 1 (from local files)
# Chọn file backup
# Nhập tên mới khi được hỏi
```

## License

MIT
