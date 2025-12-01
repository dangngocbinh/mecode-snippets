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

# Check and install fzf if needed
check_fzf() {
    if command -v fzf &> /dev/null; then
        return 0
    fi

    print_warning "fzf not found. Installing fzf for better UI experience..."

    # Detect OS and install
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew &> /dev/null; then
            brew install fzf
        else
            print_error "Homebrew not found. Please install fzf manually: brew install fzf"
            return 1
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y fzf
        elif command -v yum &> /dev/null; then
            sudo yum install -y fzf
        elif command -v pacman &> /dev/null; then
            sudo pacman -S fzf
        else
            print_error "Package manager not found. Please install fzf manually."
            return 1
        fi
    else
        print_error "Unsupported OS. Please install fzf manually."
        return 1
    fi

    if command -v fzf &> /dev/null; then
        print_success "fzf installed successfully!"
        return 0
    else
        print_error "Failed to install fzf"
        return 1
    fi
}

# Find backup files in directory
find_backup_files() {
    local backup_dir=$1
    find "$backup_dir" -type f -name "*.tar.gz" | sort
}

# Select backup files using fzf (interactive multi-select)
select_backup_files_fzf() {
    local backup_files=("$@")

    if [ ${#backup_files[@]} -eq 0 ]; then
        print_error "No backup files found" >&2
        exit 1
    fi

    echo "" >&2
    print_info "Use arrow keys to navigate, TAB to select/deselect, ENTER to confirm" >&2
    print_info "Type to search/filter backups" >&2
    echo "" >&2

    # Prepare display list with filename and size
    local display_list=()
    local file_map=()
    for file in "${backup_files[@]}"; do
        local filename=$(basename "$file")
        local size=$(du -h "$file" | cut -f1)
        display_list+=("$filename ($size)")
        file_map+=("$file")
    done

    # Use fzf with multi-select
    local selected_display=$(printf '%s\n' "${display_list[@]}" | \
        fzf --multi \
            --height=40% \
            --reverse \
            --header="Select backups (TAB to select, ENTER to confirm, ESC to select all)" \
            --bind 'esc:select-all+accept' \
            --prompt="Backups > " \
            --preview-window=hidden)

    # Map back to full file paths
    local selected=()
    if [ -z "$selected_display" ]; then
        print_info "No selection or cancelled. Selecting ALL backups..." >&2
        selected=("${backup_files[@]}")
    else
        while IFS= read -r line; do
            for i in "${!display_list[@]}"; do
                if [ "${display_list[$i]}" = "$line" ]; then
                    selected+=("${file_map[$i]}")
                    break
                fi
            done
        done <<< "$selected_display"
    fi

    echo "" >&2
    print_info "Selected backups:" >&2
    for file in "${selected[@]}"; do
        echo "  - $(basename "$file")" >&2
    done
    echo "" >&2

    # Return selected files
    printf '%s\n' "${selected[@]}"
}

# Select backup files using numbered menu (fallback)
select_backup_files() {
    local backup_files=("$@")

    if [ ${#backup_files[@]} -eq 0 ]; then
        print_error "No backup files found" >&2
        exit 1
    fi

    echo "" >&2
    print_info "Available backup files:" >&2
    echo "" >&2
    echo "  0) [Restore ALL backups]" >&2

    for i in "${!backup_files[@]}"; do
        local filename=$(basename "${backup_files[$i]}")
        local size=$(du -h "${backup_files[$i]}" | cut -f1)
        echo "  $((i+1))) $filename ($size)" >&2
    done

    echo "" >&2
    echo -e "${YELLOW}Enter backup numbers (comma-separated, e.g., 1,3,5) or 0 for all:${NC}" >&2
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
                print_warning "Invalid selection: $num (skipped)" >&2
            fi
        done
    fi

    if [ ${#selected[@]} -eq 0 ]; then
        print_error "No backups selected" >&2
        exit 1
    fi

    echo "" >&2
    print_info "Selected backups:" >&2
    for file in "${selected[@]}"; do
        echo "  - $(basename "$file")" >&2
    done

    # Return selected files (one per line to stdout)
    printf '%s\n' "${selected[@]}"
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
            mapfile -t backup_files < <(find_backup_files "$backup_dir")

            if [ ${#backup_files[@]} -eq 0 ]; then
                print_error "No backup files found in: $backup_dir"
                exit 1
            fi

            # Select backups using fzf if available, otherwise fallback to numbered menu
            if command -v fzf &> /dev/null; then
                mapfile -t selected_backups < <(select_backup_files_fzf "${backup_files[@]}")
            else
                # Try to install fzf
                if check_fzf; then
                    mapfile -t selected_backups < <(select_backup_files_fzf "${backup_files[@]}")
                else
                    print_warning "Using numbered menu (install fzf for better UI)"
                    echo ""
                    mapfile -t selected_backups < <(select_backup_files "${backup_files[@]}")
                fi
            fi

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

            # List available backup files on remote
            print_info "Fetching available backup files from remote..."
            mapfile -t remote_backup_files < <(ssh -p "$remote_port" "$remote_host" "find ${remote_path} -type f -name '*.tar.gz' ! -name '*_metadata.json' 2>/dev/null | sort")

            if [ ${#remote_backup_files[@]} -eq 0 ]; then
                print_error "No backup files found on remote server"
                exit 1
            fi

            # Select backups using fzf if available, otherwise fallback to numbered menu
            local use_fzf=false
            if command -v fzf &> /dev/null; then
                use_fzf=true
            else
                # Try to install fzf
                if check_fzf; then
                    use_fzf=true
                fi
            fi

            local selected_backup_files=()
            if [ "$use_fzf" = true ]; then
                # Prepare display list with filename and size from remote
                local display_list=()
                local file_map=()
                for remote_file in "${remote_backup_files[@]}"; do
                    local filename=$(basename "$remote_file")
                    local size=$(ssh -p "$remote_port" "$remote_host" "du -h '$remote_file' | cut -f1")
                    display_list+=("$filename ($size)")
                    file_map+=("$remote_file")
                done

                echo "" >&2
                print_info "Use arrow keys to navigate, TAB to select/deselect, ENTER to confirm" >&2
                print_info "Type to search/filter backups" >&2
                echo "" >&2

                local selected_display=$(printf '%s\n' "${display_list[@]}" | \
                    fzf --multi \
                        --height=40% \
                        --reverse \
                        --header="Select backups (TAB to select, ENTER to confirm, ESC to select all)" \
                        --bind 'esc:select-all+accept' \
                        --prompt="Remote Backups > " \
                        --preview-window=hidden)

                if [ -z "$selected_display" ]; then
                    print_info "No selection or cancelled. Selecting ALL backups..."
                    selected_backup_files=("${remote_backup_files[@]}")
                else
                    while IFS= read -r line; do
                        for i in "${!display_list[@]}"; do
                            if [ "${display_list[$i]}" = "$line" ]; then
                                selected_backup_files+=("${file_map[$i]}")
                                break
                            fi
                        done
                    done <<< "$selected_display"
                fi
            else
                # Fallback to numbered menu
                print_warning "Using numbered menu (install fzf for better UI)"
                echo ""
                print_info "Available backup files on remote:"
                echo ""
                echo "  0) [Restore ALL backups]"

                for i in "${!remote_backup_files[@]}"; do
                    local filename=$(basename "${remote_backup_files[$i]}")
                    local size=$(ssh -p "$remote_port" "$remote_host" "du -h '${remote_backup_files[$i]}' | cut -f1")
                    echo "  $((i+1))) $filename ($size)"
                done

                echo ""
                echo -e "${YELLOW}Enter backup numbers (comma-separated) or 0 for all:${NC}"
                read -r selection

                local selected_backup_files=()
                if [[ "$selection" == "0" ]]; then
                    selected_backup_files=("${remote_backup_files[@]}")
                else
                    IFS=',' read -ra numbers <<< "$selection"
                    for num in "${numbers[@]}"; do
                        num=$(echo "$num" | xargs)
                        if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -gt 0 ] && [ "$num" -le "${#remote_backup_files[@]}" ]; then
                            selected_backup_files+=("${remote_backup_files[$((num-1))]}")
                        fi
                    done
                fi

                if [ ${#selected_backup_files[@]} -eq 0 ]; then
                    print_error "No backups selected"
                    exit 1
                fi
            fi

            echo ""
            print_info "Selected backups:"
            for file in "${selected_backup_files[@]}"; do
                echo "  - $(basename "$file")"
            done

            echo ""
            read -p "Overwrite existing volumes without asking? (yes/no) [default: no]: " overwrite_all
            overwrite_all=${overwrite_all:-no}

            echo ""
            local success_count=0
            local fail_count=0

            # Create temp directory for downloaded backups
            local temp_dir=$(mktemp -d)
            trap "rm -rf $temp_dir" EXIT

            for remote_file in "${selected_backup_files[@]}"; do
                local filename=$(basename "$remote_file")
                local volume_name=$(extract_volume_name "$filename")

                echo ""
                print_info "Downloading: $filename"
                scp -P "$remote_port" "$remote_host:$remote_file" "$temp_dir/" >/dev/null 2>&1

                if [ $? -ne 0 ]; then
                    print_error "Failed to download: $filename"
                    ((fail_count++))
                    continue
                fi

                print_info "Target volume name: $volume_name"
                read -p "Press Enter to use this name, or type a new name: " custom_name

                if [ -n "$custom_name" ]; then
                    volume_name="$custom_name"
                fi

                if restore_volume_from_file "$temp_dir/$filename" "$volume_name" "$overwrite_all"; then
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
