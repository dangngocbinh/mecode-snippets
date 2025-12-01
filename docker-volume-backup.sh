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

# Get list of Docker volumes
get_volumes() {
    docker volume ls --format "{{.Name}}" | sort
}

# Select volumes using fzf (interactive multi-select)
select_volumes_fzf() {
    local volumes=("$@")

    echo "" >&2
    print_info "Use arrow keys to navigate, TAB to select/deselect, ENTER to confirm" >&2
    print_info "Type to search/filter volumes" >&2
    echo "" >&2

    # Use fzf with multi-select
    local selected=$(printf '%s\n' "${volumes[@]}" | \
        fzf --multi \
            --height=40% \
            --reverse \
            --header="Select volumes (TAB to select, ENTER to confirm, ESC to select all)" \
            --bind 'esc:select-all+accept' \
            --prompt="Volumes > " \
            --preview-window=hidden)

    # If nothing selected or user cancelled, select all
    if [ -z "$selected" ]; then
        print_info "No selection or cancelled. Selecting ALL volumes..." >&2
        selected=$(printf '%s\n' "${volumes[@]}")
    fi

    echo "" >&2
    print_info "Selected volumes:" >&2
    echo "$selected" | while read -r vol; do
        [ -n "$vol" ] && echo "  - $vol" >&2
    done
    echo "" >&2

    # Return selected volumes
    echo "$selected"
}

# Select volumes using numbered menu (fallback)
select_volumes_menu() {
    local volumes=("$@")
    local selected=()

    echo "" >&2
    print_info "Available Docker volumes:" >&2
    echo "" >&2
    echo "  0) [Select ALL volumes]" >&2

    for i in "${!volumes[@]}"; do
        echo "  $((i+1))) ${volumes[$i]}" >&2
    done

    echo "" >&2
    echo -e "${YELLOW}Enter volume numbers (comma-separated, e.g., 1,3,5) or 0 for all:${NC}" >&2
    read -r selection

    # Parse selection
    if [[ "$selection" == "0" ]]; then
        selected=("${volumes[@]}")
    else
        IFS=',' read -ra numbers <<< "$selection"
        for num in "${numbers[@]}"; do
            num=$(echo "$num" | xargs) # trim whitespace
            if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -gt 0 ] && [ "$num" -le "${#volumes[@]}" ]; then
                selected+=("${volumes[$((num-1))]}")
            else
                print_warning "Invalid selection: $num (skipped)" >&2
            fi
        done
    fi

    if [ ${#selected[@]} -eq 0 ]; then
        print_error "No volumes selected" >&2
        exit 1
    fi

    echo "" >&2
    print_info "Selected volumes:" >&2
    for vol in "${selected[@]}"; do
        echo "  - $vol" >&2
    done

    # Return selected volumes (one per line to stdout)
    printf '%s\n' "${selected[@]}"
}

# Backup volume to tar.gz with metadata
backup_volume_to_file() {
    local volume_name=$1
    local output_dir=$2
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${output_dir}/${volume_name}_${timestamp}.tar.gz"

    print_info "Backing up volume: $volume_name"

    # Get volume metadata
    local volume_info=$(docker volume inspect "$volume_name" 2>/dev/null)
    if [ $? -ne 0 ]; then
        print_error "Volume $volume_name does not exist"
        return 1
    fi

    local mountpoint=$(echo "$volume_info" | grep -o '"Mountpoint": "[^"]*"' | cut -d'"' -f4)

    # Create metadata file
    local metadata_file="${output_dir}/${volume_name}_${timestamp}_metadata.json"
    echo "$volume_info" > "$metadata_file"

    # Create tar.gz of volume data
    print_info "Creating archive: $backup_file"
    docker run --rm \
        -v "${volume_name}:/source:ro" \
        -v "${output_dir}:/backup" \
        alpine \
        tar czf "/backup/$(basename "$backup_file")" -C /source .

    if [ $? -eq 0 ]; then
        # Add metadata to the archive
        tar --append --file="${backup_file%.gz}" -C "$(dirname "$metadata_file")" "$(basename "$metadata_file")" 2>/dev/null || true
        gzip -f "${backup_file%.gz}" 2>/dev/null || true

        rm -f "$metadata_file"

        local size=$(du -h "$backup_file" | cut -f1)
        print_success "Backup completed: $backup_file ($size)"
        echo "$backup_file"
        return 0
    else
        print_error "Failed to backup volume: $volume_name"
        rm -f "$metadata_file"
        return 1
    fi
}

# Sync volume to remote VPS as tar.gz file
sync_volume_to_remote() {
    local volume_name=$1
    local remote_host=$2
    local remote_port=$3
    local remote_path=$4
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_filename="${volume_name}_${timestamp}.tar.gz"

    print_info "Backing up volume: $volume_name to $remote_host:$remote_port"

    # Get volume metadata
    local volume_info=$(docker volume inspect "$volume_name" 2>/dev/null)
    if [ $? -ne 0 ]; then
        print_error "Volume $volume_name does not exist"
        return 1
    fi

    # Create remote directory
    print_info "Creating remote directory: ${remote_path}"
    ssh -p "$remote_port" "$remote_host" "mkdir -p ${remote_path}" 2>/dev/null || true

    # Create tar.gz and send to remote directly via pipe
    print_info "Creating and transferring backup file: $backup_filename"
    docker run --rm \
        -v "${volume_name}:/source:ro" \
        alpine \
        tar czf - -C /source . | \
        ssh -p "$remote_port" "$remote_host" "cat > ${remote_path}/${backup_filename}"

    local transfer_status=$?

    if [ $transfer_status -eq 0 ]; then
        # Send metadata
        local metadata_filename="${volume_name}_${timestamp}_metadata.json"
        echo "$volume_info" | ssh -p "$remote_port" "$remote_host" "cat > ${remote_path}/${metadata_filename}"

        # Get file size from remote
        local remote_size=$(ssh -p "$remote_port" "$remote_host" "du -h ${remote_path}/${backup_filename} | cut -f1")

        print_success "Successfully backed up: $backup_filename ($remote_size) to $remote_host:${remote_path}"
        return 0
    else
        print_error "Failed to backup volume: $volume_name"
        # Try to cleanup failed backup on remote
        ssh -p "$remote_port" "$remote_host" "rm -f ${remote_path}/${backup_filename}" 2>/dev/null || true
        return 1
    fi
}

# Main function
main() {
    echo ""
    echo "=========================================="
    echo "  Docker Volume Backup Tool"
    echo "=========================================="
    echo ""

    check_docker

    # Get volumes
    mapfile -t volumes_list < <(get_volumes)

    if [ ${#volumes_list[@]} -eq 0 ]; then
        print_error "No Docker volumes found"
        exit 1
    fi

    # Select volumes using fzf if available, otherwise fallback to numbered menu
    if command -v fzf &> /dev/null; then
        mapfile -t selected_volumes < <(select_volumes_fzf "${volumes_list[@]}")
    else
        print_warning "fzf not found. Using numbered menu (install fzf for better UI)"
        echo ""
        mapfile -t selected_volumes < <(select_volumes_menu "${volumes_list[@]}")
    fi

    # Ask for destination
    echo ""
    print_info "Select backup destination:"
    echo "  1) Export to local file (tar.gz)"
    echo "  2) Sync to remote VPS (rsync)"
    echo ""
    read -p "Enter choice (1 or 2): " dest_choice

    case $dest_choice in
        1)
            # Export to file
            read -p "Enter output directory [default: ./backups]: " output_dir
            output_dir=${output_dir:-./backups}

            # Create output directory
            mkdir -p "$output_dir"
            output_dir=$(cd "$output_dir" && pwd) # Get absolute path

            print_info "Output directory: $output_dir"
            echo ""

            local success_count=0
            local fail_count=0

            for volume in "${selected_volumes[@]}"; do
                if backup_volume_to_file "$volume" "$output_dir"; then
                    ((success_count++))
                else
                    ((fail_count++))
                fi
                echo ""
            done

            echo "=========================================="
            print_success "Backup completed: $success_count succeeded, $fail_count failed"
            print_info "Backup location: $output_dir"
            echo "=========================================="
            ;;

        2)
            # Sync to remote VPS
            read -p "Enter remote host (user@ip): " remote_host
            read -p "Enter SSH port [default: 22]: " remote_port
            remote_port=${remote_port:-22}
            read -p "Enter remote path [default: /tmp/docker-volumes]: " remote_path
            remote_path=${remote_path:-/tmp/docker-volumes}

            print_info "Remote destination: $remote_host:$remote_port:$remote_path"
            echo ""

            # Test SSH connection
            print_info "Testing SSH connection..."
            if ! ssh -p "$remote_port" -o ConnectTimeout=5 "$remote_host" "echo 'Connection successful'" &> /dev/null; then
                print_error "Cannot connect to remote host"
                exit 1
            fi
            print_success "SSH connection OK"
            echo ""

            local success_count=0
            local fail_count=0

            for volume in "${selected_volumes[@]}"; do
                if sync_volume_to_remote "$volume" "$remote_host" "$remote_port" "$remote_path"; then
                    ((success_count++))
                else
                    ((fail_count++))
                fi
                echo ""
            done

            echo "=========================================="
            print_success "Backup completed: $success_count succeeded, $fail_count failed"
            print_info "Remote location: $remote_host:$remote_path"
            print_info "Backup files are saved as .tar.gz on remote server"
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
