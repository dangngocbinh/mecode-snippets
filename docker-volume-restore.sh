#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored message
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if Docker is running
check_docker() {
    if ! docker info &> /dev/null; then
        print_error "Docker is not running or you don't have permission to access it"
        exit 1
    fi
}

# Find backup files in directory
find_backup_files() {
    local backup_dir=$1
    find "$backup_dir" -type f -name "*.tar.gz" | sort
}

# Select backup files
select_backup_files() {
    local backup_files=("$@")

    if [ ${#backup_files[@]} -eq 0 ]; then
        print_error "No backup files found"
        exit 1
    fi

    echo ""
    print_info "Available backup files:"
    echo ""
    echo "  0) [Restore ALL backups]"

    for i in "${!backup_files[@]}"; do
        local filename=$(basename "${backup_files[$i]}")
        local size=$(du -h "${backup_files[$i]}" | cut -f1)
        echo "  $((i+1))) $filename ($size)"
    done

    echo ""
    echo -e "${YELLOW}Enter backup numbers (comma-separated, e.g., 1,3,5) or 0 for all:${NC}"
    read -r selection

    local selected=()

    # Parse selection
    if [[ "$selection" == "0" ]]; then
        selected=("${backup_files[@]}")
    else
        IFS=',' read -ra numbers <<< "$selection"
        for num in "${numbers[@]}"; do
            num=$(echo "$num" | xargs) # trim whitespace
            if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -gt 0 ] && [ "$num" -le "${#backup_files[@]}" ]; then
                selected+=("${backup_files[$((num-1))]}")
            else
                print_warning "Invalid selection: $num (skipped)"
            fi
        done
    fi

    if [ ${#selected[@]} -eq 0 ]; then
        print_error "No backups selected"
        exit 1
    fi

    echo ""
    print_info "Selected backups:"
    for file in "${selected[@]}"; do
        echo "  - $(basename "$file")"
    done

    echo "${selected[@]}"
}

# Extract volume name from backup filename
extract_volume_name() {
    local backup_file=$1
    local filename=$(basename "$backup_file")
    # Remove timestamp and extension (format: volumename_YYYYMMDD_HHMMSS.tar.gz)
    echo "$filename" | sed -E 's/_[0-9]{8}_[0-9]{6}\.tar\.gz$//'
}

# Restore volume from backup file
restore_volume_from_file() {
    local backup_file=$1
    local target_volume=$2
    local overwrite=$3

    print_info "Restoring from: $(basename "$backup_file")"

    # Check if backup file exists
    if [ ! -f "$backup_file" ]; then
        print_error "Backup file not found: $backup_file"
        return 1
    fi

    # Check if volume already exists
    if docker volume inspect "$target_volume" &> /dev/null; then
        if [ "$overwrite" != "yes" ]; then
            print_warning "Volume '$target_volume' already exists"
            read -p "Overwrite existing volume? (yes/no): " confirm
            if [ "$confirm" != "yes" ]; then
                print_info "Skipping: $target_volume"
                return 0
            fi
        fi
        print_info "Removing existing volume: $target_volume"
        docker volume rm "$target_volume" 2>/dev/null || {
            print_error "Cannot remove volume '$target_volume' (may be in use)"
            return 1
        }
    fi

    # Create new volume
    print_info "Creating volume: $target_volume"
    docker volume create "$target_volume" > /dev/null

    if [ $? -ne 0 ]; then
        print_error "Failed to create volume: $target_volume"
        return 1
    fi

    # Restore data to volume
    print_info "Restoring data to volume: $target_volume"

    # Create absolute path for backup file
    local abs_backup_file=$(cd "$(dirname "$backup_file")" && pwd)/$(basename "$backup_file")

    docker run --rm \
        -v "${target_volume}:/target" \
        -v "$(dirname "$abs_backup_file"):/backup:ro" \
        alpine \
        sh -c "cd /target && tar xzf /backup/$(basename "$abs_backup_file") --exclude='*_metadata.json' 2>/dev/null || tar xzf /backup/$(basename "$abs_backup_file")"

    if [ $? -eq 0 ]; then
        print_success "Successfully restored: $target_volume"
        return 0
    else
        print_error "Failed to restore volume: $target_volume"
        docker volume rm "$target_volume" 2>/dev/null
        return 1
    fi
}

# Restore from remote VPS
restore_from_remote() {
    local remote_host=$1
    local remote_port=$2
    local remote_path=$3
    local target_volume=$4
    local overwrite=$5

    print_info "Restoring from remote: $remote_host:$remote_path"

    # Check if volume already exists
    if docker volume inspect "$target_volume" &> /dev/null; then
        if [ "$overwrite" != "yes" ]; then
            print_warning "Volume '$target_volume' already exists"
            read -p "Overwrite existing volume? (yes/no): " confirm
            if [ "$confirm" != "yes" ]; then
                print_info "Skipping: $target_volume"
                return 0
            fi
        fi
        print_info "Removing existing volume: $target_volume"
        docker volume rm "$target_volume" 2>/dev/null || {
            print_error "Cannot remove volume '$target_volume' (may be in use)"
            return 1
        }
    fi

    # Create new volume
    print_info "Creating volume: $target_volume"
    docker volume create "$target_volume" > /dev/null

    if [ $? -ne 0 ]; then
        print_error "Failed to create volume: $target_volume"
        return 1
    fi

    # Create temporary container
    local container_name="volume_restore_${target_volume}_$$"

    docker run -d --rm \
        --name "$container_name" \
        -v "${target_volume}:/data" \
        alpine \
        sleep 3600 > /dev/null

    if [ $? -ne 0 ]; then
        print_error "Failed to create temporary container"
        docker volume rm "$target_volume" 2>/dev/null
        return 1
    fi

    # Transfer data from remote
    print_info "Transferring data from remote..."
    ssh -p "$remote_port" "$remote_host" "cd ${remote_path}/${target_volume} && tar cf - ." | docker cp - "${container_name}:/data/"
    local transfer_status=$?

    # Cleanup
    docker stop "$container_name" > /dev/null 2>&1

    if [ $transfer_status -eq 0 ]; then
        print_success "Successfully restored: $target_volume"
        return 0
    else
        print_error "Failed to restore volume: $target_volume"
        docker volume rm "$target_volume" 2>/dev/null
        return 1
    fi
}

# Main function
main() {
    echo ""
    echo "=========================================="
    echo "  Docker Volume Restore Tool"
    echo "=========================================="
    echo ""

    check_docker

    # Ask for restore source
    print_info "Select restore source:"
    echo "  1) Restore from local backup files (tar.gz)"
    echo "  2) Restore from remote VPS"
    echo ""
    read -p "Enter choice (1 or 2): " source_choice

    case $source_choice in
        1)
            # Restore from local files
            read -p "Enter backup directory [default: ./backups]: " backup_dir
            backup_dir=${backup_dir:-./backups}

            if [ ! -d "$backup_dir" ]; then
                print_error "Directory not found: $backup_dir"
                exit 1
            fi

            backup_dir=$(cd "$backup_dir" && pwd) # Get absolute path

            # Find backup files
            local backup_files=($(find_backup_files "$backup_dir"))

            if [ ${#backup_files[@]} -eq 0 ]; then
                print_error "No backup files found in: $backup_dir"
                exit 1
            fi

            # Select backups
            local selected_backups=($(select_backup_files "${backup_files[@]}"))

            echo ""
            read -p "Overwrite existing volumes without asking? (yes/no) [default: no]: " overwrite_all
            overwrite_all=${overwrite_all:-no}

            echo ""
            local success_count=0
            local fail_count=0

            for backup_file in "${selected_backups[@]}"; do
                local volume_name=$(extract_volume_name "$backup_file")

                echo ""
                print_info "Target volume name: $volume_name"
                read -p "Press Enter to use this name, or type a new name: " custom_name

                if [ -n "$custom_name" ]; then
                    volume_name="$custom_name"
                fi

                if restore_volume_from_file "$backup_file" "$volume_name" "$overwrite_all"; then
                    ((success_count++))
                else
                    ((fail_count++))
                fi
                echo ""
            done

            echo "=========================================="
            print_success "Restore completed: $success_count succeeded, $fail_count failed"
            echo "=========================================="
            ;;

        2)
            # Restore from remote VPS
            read -p "Enter remote host (user@ip): " remote_host
            read -p "Enter SSH port [default: 22]: " remote_port
            remote_port=${remote_port:-22}
            read -p "Enter remote path [default: /tmp/docker-volumes]: " remote_path
            remote_path=${remote_path:-/tmp/docker-volumes}

            print_info "Remote source: $remote_host:$remote_port:$remote_path"
            echo ""

            # Test SSH connection
            print_info "Testing SSH connection..."
            if ! ssh -p "$remote_port" -o ConnectTimeout=5 "$remote_host" "echo 'Connection successful'" &> /dev/null; then
                print_error "Cannot connect to remote host"
                exit 1
            fi
            print_success "SSH connection OK"
            echo ""

            # List available volumes on remote
            print_info "Fetching available volumes from remote..."
            local remote_volumes=($(ssh -p "$remote_port" "$remote_host" "ls -1d ${remote_path}/*/ 2>/dev/null | xargs -n1 basename" | grep -v "_metadata.json"))

            if [ ${#remote_volumes[@]} -eq 0 ]; then
                print_error "No volumes found on remote server"
                exit 1
            fi

            echo ""
            print_info "Available volumes on remote:"
            echo ""
            echo "  0) [Restore ALL volumes]"

            for i in "${!remote_volumes[@]}"; do
                echo "  $((i+1))) ${remote_volumes[$i]}"
            done

            echo ""
            echo -e "${YELLOW}Enter volume numbers (comma-separated) or 0 for all:${NC}"
            read -r selection

            local selected_volumes=()

            if [[ "$selection" == "0" ]]; then
                selected_volumes=("${remote_volumes[@]}")
            else
                IFS=',' read -ra numbers <<< "$selection"
                for num in "${numbers[@]}"; do
                    num=$(echo "$num" | xargs)
                    if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -gt 0 ] && [ "$num" -le "${#remote_volumes[@]}" ]; then
                        selected_volumes+=("${remote_volumes[$((num-1))]}")
                    fi
                done
            fi

            if [ ${#selected_volumes[@]} -eq 0 ]; then
                print_error "No volumes selected"
                exit 1
            fi

            echo ""
            read -p "Overwrite existing volumes without asking? (yes/no) [default: no]: " overwrite_all
            overwrite_all=${overwrite_all:-no}

            local success_count=0
            local fail_count=0

            for volume in "${selected_volumes[@]}"; do
                echo ""
                if restore_from_remote "$remote_host" "$remote_port" "$remote_path" "$volume" "$overwrite_all"; then
                    ((success_count++))
                else
                    ((fail_count++))
                fi
            done

            echo ""
            echo "=========================================="
            print_success "Restore completed: $success_count succeeded, $fail_count failed"
            echo "=========================================="
            ;;

        *)
            print_error "Invalid choice"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
