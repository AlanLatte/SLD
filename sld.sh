#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -euo pipefail

# Color codes for output
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
RED="\033[0;31m"
NC="\033[0m" # No Color

# Functions for output messages
log_info() { echo -e "${CYAN}[INFO] $1${NC}"; }
log_success() { echo -e "${GREEN}[SUCCESS] $1${NC}"; }
log_warning() { echo -e "${YELLOW}[WARNING] $1${NC}"; }
log_error() { echo -e "${RED}[ERROR] $1${NC}"; }

# Function to show help
show_help() {
    cat <<EOF
Usage: sld [options] [arguments]
Options:
  -h, --help                        Show this help message and exit.
  -d, --database DATABASE_NAME      Specify the database name.
  -u, --user USERNAME               Specify the user name.
  -p, --password                    Prompt for user password securely.
  -du, --database-user DB_NAME USER Create a new database with a new user.
  -b, --backup [DB_NAME]            Backup the specified database or default.
  -r, --restore FILE                Restore the database from a backup file.
  -a, --apply-sql FILE              Apply an SQL file to the database.
  -l, --list [databases|users]      List databases or users.
  -del, --delete [database|user]    Delete a database or user.
  -i, --interactive                 Start in interactive mode.

Examples:
  sld --database my_database
  sld --user my_user
  sld --database-user my_db my_user
  sld --backup my_database
  sld --restore backup.sql --database my_database
  sld --apply-sql script.sql --database my_database
  sld --list databases
  sld --delete database my_database
EOF
}

# Function to parse options
parse_options() {
    if [[ $# -eq 0 ]]; then
        log_error "No arguments provided."
        show_help
        exit 1
    fi

    ACTION=""
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--database)
                DB_NAME="$2"
                shift 2
                ;;
            -u|--user)
                USER_NAME="$2"
                shift 2
                ;;
            -p|--password)
                if [[ $# -gt 1 && "$2" != -* ]]; then
                    USER_PASSWORD="$2"
                    PROMPT_PASSWORD="false"
                    shift 2
                else
                    PROMPT_PASSWORD="true"
                    shift
                fi
                ;;
            -du|--database-user)
                ACTION="create_database_user"
                DB_NAME="$2"
                USER_NAME="$3"
                shift 3
                ;;
            -b|--backup)
                ACTION="backup_database"
                DB_NAME="${2:-}"
                shift
                if [[ $# -gt 0 && ! "$1" =~ ^- ]]; then
                    DB_NAME="$1"
                    shift
                fi
                ;;
            -r|--restore)
                ACTION="restore_database"
                BACKUP_FILE="$2"
                shift 2
                ;;
            -a|--apply-sql)
                ACTION="apply_sql_file"
                SQL_FILE="$2"
                shift 2
                ;;
            -l|--list)
                ACTION="list_items"
                LIST_TYPE="$2"
                shift 2
                ;;
            -del|--delete)
                ACTION="delete_item"
                DELETE_TYPE="$2"
                DELETE_NAME="$3"
                shift 3
                ;;
            -i|--interactive)
                ACTION="interactive_mode"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Default actions for standalone options
    if [[ -z "${ACTION:-}" ]]; then
        if [[ -n "${DB_NAME:-}" && -z "${USER_NAME:-}" ]]; then
            ACTION="create_database"
        elif [[ -n "${USER_NAME:-}" && -z "${DB_NAME:-}" ]]; then
            ACTION="create_user"
        elif [[ -n "${USER_NAME:-}" && -n "${DB_NAME:-}" ]]; then
            ACTION="create_database_user"
        fi
    fi
}

# Function to prompt for password securely
prompt_password() {
    read -s -p "Enter password for user $USER_NAME: " USER_PASSWORD
    echo
}

# Function to check if user exists
user_exists() {
    if psql_exec -tAc "SELECT 1 FROM pg_roles WHERE rolname='$1'" | grep -q 1; then
        return 0
    else
        return 1
    fi
}

# Function to check if database exists
database_exists() {
    if psql_exec -tAc "SELECT 1 FROM pg_database WHERE datname='$1'" | grep -q 1; then
        return 0
    else
        return 1
    fi
}

# Function to execute psql commands
psql_exec() {
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$DB_SUPERUSER" "$@"
}

# Function to execute pg_dump commands
pg_dump_exec() {
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" pg_dump "$@"
}

# Function to create a new user
create_user() {
    if user_exists "$USER_NAME"; then
        log_warning "User '$USER_NAME' already exists."
        return
    fi

    if [[ "${PROMPT_PASSWORD:-false}" == "true" ]]; then
        prompt_password
    else
        USER_PASSWORD="${USER_PASSWORD:-default_password}"
    fi

    log_info "Creating user '$USER_NAME'..."
    psql_exec -c "CREATE USER \"$USER_NAME\" WITH PASSWORD '$USER_PASSWORD';"
    log_success "User '$USER_NAME' created successfully."
}

# Function to create a new database
create_database() {
    if database_exists "$DB_NAME"; then
        log_warning "Database '$DB_NAME' already exists."
        return
    fi

    if ! user_exists "$USER_NAME"; then
        log_info "User '$USER_NAME' does not exist or is not set. Using superuser '$DB_SUPERUSER' as the owner."
        USER_NAME="$DB_SUPERUSER"
    fi

    log_info "Creating database '$DB_NAME'..."
    psql_exec -c "CREATE DATABASE \"$DB_NAME\" OWNER \"$USER_NAME\";"
    log_success "Database '$DB_NAME' created successfully."
}

# Function to create a database and user
create_database_user() {
    create_user
    create_database
}

# Function to backup database
backup_database() {
    local db_name="${DB_NAME:-$DEFAULT_DB}"
    if ! database_exists "$db_name"; then
        log_error "Database '$db_name' does not exist."
        exit 1
    fi
    local backup_file="backup_${db_name}_$(date +'%Y%m%d_%H%M%S').sql"
    log_info "Backing up database '$db_name'..."
    pg_dump_exec --no-owner -U "$DB_SUPERUSER" -d "$db_name" > "$backup_file"
    log_success "Database '$db_name' backed up successfully as '$backup_file'."
}

# Function to restore database
restore_database() {
    if [[ ! -f "$BACKUP_FILE" ]]; then
        log_error "Backup file '$BACKUP_FILE' does not exist."
        exit 1
    fi

    if [[ -z "${DB_NAME:-}" ]]; then
        log_error "No database specified. Please provide a database name using --database."
        exit 1
    fi

    if ! database_exists "$DB_NAME"; then
        log_info "Database '$DB_NAME' does not exist. Creating it..."
        create_database
    fi

    log_info "Restoring database '$DB_NAME' from '$BACKUP_FILE'..."

    # Restore the backup into the specified database
    cat "$BACKUP_FILE" | docker exec -i -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$DB_SUPERUSER" -d "$DB_NAME"

    log_success "Database '$DB_NAME' restored successfully from '$BACKUP_FILE'."
}

# Function to apply SQL file to a specific database
apply_sql_file() {
    if [[ ! -f "$SQL_FILE" ]]; then
        log_error "SQL file '$SQL_FILE' does not exist."
        exit 1
    fi

    if [[ -z "${DB_NAME:-}" ]]; then
        log_error "No database specified. Please provide a database name using --database."
        exit 1
    fi

    if ! database_exists "$DB_NAME"; then
        log_info "Database '$DB_NAME' does not exist. Creating it..."
        create_database
    fi

    log_info "Applying SQL file '$SQL_FILE' to database '$DB_NAME'..."

    output=$(cat "$SQL_FILE" | docker exec -i -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER_NAME" psql -U "$DB_SUPERUSER" -d "$DB_NAME" 2>&1)

    if [[ $? -ne 0 ]]; then
        log_error "Failed to apply SQL file '$SQL_FILE' to database '$DB_NAME'."
        echo "$output"
        exit 1
    fi

    log_success "SQL file '$SQL_FILE' applied successfully to database '$DB_NAME'."
}

# Function to list databases or users
list_items() {
    case "$LIST_TYPE" in
        databases)
            log_info "Listing databases..."
            psql_exec -c "\l"
            ;;
        users)
            log_info "Listing users..."
            psql_exec -c "\du"
            ;;
        *)
            log_error "Unknown list type: $LIST_TYPE"
            exit 1
            ;;
    esac
}

# Function to delete database or user
delete_item() {
    case "$DELETE_TYPE" in
        database)
            if ! database_exists "$DELETE_NAME"; then
                log_error "Database '$DELETE_NAME' does not exist."
                exit 1
            fi
            log_info "Deleting database '$DELETE_NAME'..."
            psql_exec -c "DROP DATABASE \"$DELETE_NAME\";"
            log_success "Database '$DELETE_NAME' deleted successfully."
            ;;
        user)
            if ! user_exists "$DELETE_NAME"; then
                log_error "User '$DELETE_NAME' does not exist."
                exit 1
            fi
            log_info "Deleting user '$DELETE_NAME'..."
            psql_exec -c "DROP USER \"$DELETE_NAME\";"
            log_success "User '$DELETE_NAME' deleted successfully."
            ;;
        *)
            log_error "Unknown delete type: $DELETE_TYPE"
            exit 1
            ;;
    esac
}

# Function for interactive mode
interactive_mode() {
    log_info "Starting interactive mode. Type 'exit' to quit."
    while true; do
        echo -e "\nAvailable actions:"
        echo "1) Create a new database"
        echo "2) Create a new user"
        echo "3) Create a database and user"
        echo "4) Backup a database"
        echo "5) Restore a database"
        echo "6) Apply an SQL file"
        echo "7) List databases"
        echo "8) List users"
        echo "9) Delete a database"
        echo "10) Delete a user"
        echo "11) Exit"

        read -rp "Choose an option [1-11]: " choice

        case "$choice" in
            1)
                read -rp "Enter database name: " DB_NAME
                create_database
                ;;
            2)
                read -rp "Enter user name: " USER_NAME
                prompt_password
                create_user
                ;;
            3)
                read -rp "Enter database name: " DB_NAME
                read -rp "Enter user name: " USER_NAME
                prompt_password
                create_database_user
                ;;
            4)
                read -rp "Enter database name to backup: " DB_NAME
                backup_database
                ;;
            5)
                read -rp "Enter backup file to restore: " BACKUP_FILE
                read -rp "Enter database name to restore into: " DB_NAME
                restore_database
                ;;
            6)
                read -rp "Enter SQL file to apply: " SQL_FILE
                read -rp "Enter database name to apply SQL file: " DB_NAME
                apply_sql_file
                ;;
            7)
                LIST_TYPE="databases"
                list_items
                ;;
            8)
                LIST_TYPE="users"
                list_items
                ;;
            9)
                read -rp "Enter database name to delete: " DELETE_NAME
                DELETE_TYPE="database"
                delete_item
                ;;
            10)
                read -rp "Enter user name to delete: " DELETE_NAME
                DELETE_TYPE="user"
                delete_item
                ;;
            11)
                echo "Exiting interactive mode."
                break
                ;;
            *)
                echo "Invalid option. Please choose a number between 1 and 11."
                ;;
        esac
    done
}

# Function to detect running PostgreSQL containers
detect_container() {
    local containers
    containers=$(docker ps --format "{{.Names}} {{.Image}}" | awk '$2 ~ /^postgres/ {print $1}')
    if [[ -z "$containers" ]]; then
        log_error "No running PostgreSQL containers found."
        exit 1
    fi

    IFS=$'\n' read -r -d '' -a container_array <<<"$containers" || true

    if [[ ${#container_array[@]} -eq 1 ]]; then
        CONTAINER_NAME="${container_array[0]}"
        log_info "Using container '$CONTAINER_NAME'."
    else
        log_info "Multiple PostgreSQL containers found:"
        select cname in "${container_array[@]}"; do
            CONTAINER_NAME="$cname"
            break
        done
    fi

    # Get environment variables from the container
    container_env=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$CONTAINER_NAME")
    POSTGRES_USER=$(echo "$container_env" | grep '^POSTGRES_USER=' | cut -d'=' -f2)
    POSTGRES_PASSWORD=$(echo "$container_env" | grep '^POSTGRES_PASSWORD=' | cut -d'=' -f2)
    PGDATA=$(echo "$container_env" | grep '^PGDATA=' | cut -d'=' -f2)
    # Set default values if not set
    POSTGRES_USER="${POSTGRES_USER:-postgres}"
    POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"
    PGDATA="${PGDATA:-/var/lib/postgresql/data}"

    log_info "Detected credentials: POSTGRES_USER='$POSTGRES_USER'"
}

# Function to display the creator's signature
show_created_by() {
    echo -e "${YELLOW}"
    echo "                                    Created by                "
    echo "                           ──────────────────────────────     "
    echo "                                   ┏┓┓     ┓                  "
    echo "                                   ┣┫┃┏┓┏┓ ┃ ┏┓╋╋┏┓           "
    echo "                               ━━━━┛┗┗┗┻┛┗•┗┛┗┻┗┗┗━━━━        "
    echo -e "${NC}"
}

# Main script execution
main() {
    parse_options "$@"

    # Detect PostgreSQL container and get credentials
    detect_container

    # Set default values if not set
    DB_SUPERUSER="$POSTGRES_USER"
    USER_NAME="${USER_NAME:-$DB_SUPERUSER}"
    DEFAULT_DB="${DEFAULT_DB:-$POSTGRES_USER}"

    # Execute the action
    case "${ACTION:-}" in
        create_user)
            create_user
            ;;
        create_database)
            create_database
            ;;
        create_database_user)
            create_database_user
            ;;
        backup_database)
            backup_database
            ;;
        restore_database)
            restore_database
            ;;
        apply_sql_file)
            apply_sql_file
            ;;
        list_items)
            list_items
            ;;
        delete_item)
            delete_item
            ;;
        interactive_mode)
            interactive_mode
            ;;
        *)
            log_error "No valid action specified."
            show_help
            exit 1
            ;;
    esac

    show_created_by
}

# Run the main function
main "$@"
