#!/bin/bash

# Цвета для вывода
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
RED="\033[0;31m"
NC="\033[0m" # No Color

# Функция для вывода справочной информации
show_help() {
    echo -e "${CYAN}"
    echo "                            $\$$\$$\$\  $\$\       $\$$\$$\$$\  "
    echo "                           $\$  __$\$\ $\$ |      $\$  __$\$\ "
    echo "                           $\$ /  \__|$\$ |      $\$ |  $\$ |"
    echo "                           \$$\$$\$$\   $\$ |      $\$ |  $\$ |"
    echo "                            \____$\$\ $\$ |      $\$ |  $\$ |"
    echo "                           $\$\   $\$ |$\$ |      $\$ |  $\$ |"
    echo "                            \$$\$$\$$  |$\$$\$$\$$\$\ $\$\$$\$$\$  |"
    echo "                            \______/ \________|\_______/ "
    echo -e "${NC}"
    echo
    echo "Usage: sld [options] [arguments]"
    echo "Options:"
    echo "-h/--help                               - Show usage."
    echo "-d/--database [database_name]           - Create new database."
    echo "-u/--user [username] [password]         - Create new user."
    echo "-du/--database-user [database_name] [username] [password] - Create new database with a new user."
    echo
    echo "Example:"
    echo "sld --database my_database              - Create a new database 'my_database'."
    echo "sld --user my_user my_password          - Create a new user 'my_user' with 'my_password'."
    echo "sld --database-user my_database my_user my_password - Create 'my_database' with user 'my_user' and password 'my_password'."
    show_created_by
}

# Функция для проверки запущенного контейнера
check_container_running() {
    container_id_or_name=$1
    if [ -z "$(docker ps -q -f id=$container_id_or_name)" ] && [ -z "$(docker ps -q -f name=$container_id_or_name)" ]; then
        echo -e "${RED}Контейнер с именем или ID $container_id_or_name не запущен.${NC}"
        exit 1
    fi
}

# Функция для получения значения переменной среды из контейнера
get_env_var() {
    docker exec "$1" printenv "$2"
}

# Функция для получения порта из docker inspect
get_container_port() {
    docker inspect --format='{{(index (index .NetworkSettings.Ports "5432/tcp") 0).HostPort}}' "$1"
}

# Функция для вывода авторства
show_created_by() {
    echo -e "${YELLOW}"
    echo "                                    Created by                "
    echo "                           ──────────────────────────────     "
    echo "                                   ┏┓┓     ┓                  "
    echo "                                   ┣┫┃┏┓┏┓ ┃ ┏┓╋╋┏┓           "
    echo "                               ━━━━┛┗┗┗┻┛┗•┗┛┗┻┗┗┗━━━━        "
    echo -e "${NC}"
}

# Проверка на наличие флага --help или -h
if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    show_help
    exit 0
fi

# Выводим список запущенных контейнеров
docker ps

# Запрашиваем у пользователя ID или имя контейнера
read -r -p "Enter container hash or name: " container_hash_or_name

# Проверяем, запущен ли контейнер
check_container_running "$container_hash_or_name"

# Получаем пользователя и пароль из ENV переменных контейнера
database_user=$(get_env_var "$container_hash_or_name" "POSTGRES_USER")
database_password=$(get_env_var "$container_hash_or_name" "POSTGRES_PASSWORD")

# Получаем порт, на котором работает Postgres внутри контейнера
pg_port=$(get_container_port "$container_hash_or_name")

echo -e "${GREEN}Database user detected: $database_user${NC}"
echo "------------------------"

# Если аргументы командной строки не заданы, выполняем пошаговый режим
if [[ -z "$1" ]]; then
    # Запрос на создание базы данных или пользователя
    read -r -p "Do you want to create a (D)atabase or a (U)ser? [D/U]: " create_choice

    # Логика создания базы данных
    if [[ "$create_choice" =~ ^[Dd]$ ]]; then
        read -r -p "Enter database name: " database_name
        read -r -p "Do you need to create a new user for this database? [y/N]: " create_user_choice

        if [[ "$create_user_choice" =~ ^[Yy]$ ]]; then
            read -r -p "Enter new database user: " new_user
            read -r -p "Enter new user password: " new_user_password

            echo -e "${CYAN}Creating new user: $new_user${NC}"
            docker exec -it "$container_hash_or_name" psql -U "$database_user" -c "CREATE USER $new_user WITH PASSWORD '$new_user_password';" &> /dev/null
            
            # Логируем нового пользователя
            echo "$(date) - User created: $new_user with password: $new_user_password" >> user_creation.log

            # Заменяем пользователя и пароль на нового пользователя
            database_user=$new_user
            database_password=$new_user_password
        fi

        echo -e "${CYAN}Creating new database: $database_name${NC}"
        docker exec -it "$container_hash_or_name" psql -U "$database_user" -c "CREATE DATABASE $database_name;" &> /dev/null

        echo -e "${CYAN}Creating new test database: test_$database_name${NC}"
        docker exec -it "$container_hash_or_name" psql -U "$database_user" -c "CREATE DATABASE test_$database_name;" &> /dev/null

    # Логика создания пользователя
    elif [[ "$create_choice" =~ ^[Uu]$ ]]; then
        read -r -p "Enter new database user: " new_user
        read -r -p "Enter new user password: " new_user_password
        read -r -p "Do you need to create a new database for this user? [y/N]: " create_db_choice

        echo -e "${CYAN}Creating new user: $new_user${NC}"
        docker exec -it "$container_hash_or_name" psql -U "$database_user" -c "CREATE USER $new_user WITH PASSWORD '$new_user_password';" &> /dev/null
        
        # Логируем нового пользователя
        echo "$(date) - User created: $new_user with password: $new_user_password" >> user_creation.log

        if [[ "$create_db_choice" =~ ^[Yy]$ ]]; then
            read -r -p "Enter database name: " database_name

            echo -e "${CYAN}Creating new database: $database_name${NC}"
            docker exec -it "$container_hash_or_name" psql -U "$new_user" -c "CREATE DATABASE $database_name;" &> /dev/null

            echo -e "${CYAN}Creating new test database: test_$database_name${NC}"
            docker exec -it "$container_hash_or_name" psql -U "$new_user" -c "CREATE DATABASE test_$database_name;" &> /dev/null

            # Заменяем пользователя и пароль на нового пользователя
            database_user=$new_user
            database_password=$new_user_password
        fi
    else
        echo -e "${RED}Invalid option selected. Please choose either 'D' for Database or 'U' for User.${NC}"
        exit 1
    fi

# Если заданы аргументы командной строки, обрабатываем их
else
    if [[ "$1" == "--database" ]] || [[ "$1" == "-d" ]]; then
        database_name=$2
        echo -e "${CYAN}Creating new database: $database_name${NC}"
        docker exec -it "$container_hash_or_name" psql -U "$database_user" -c "CREATE DATABASE $database_name;" &> /dev/null

        echo -e "${CYAN}Creating new test database: test_$database_name${NC}"
        docker exec -it "$container_hash_or_name" psql -U "$database_user" -c "CREATE DATABASE test_$database_name;" &> /dev/null

    elif [[ "$1" == "--user" ]] || [[ "$1" == "-u" ]]; then
        new_user=$2
        new_user_password=$3
        echo -e "${CYAN}Creating new user: $new_user${NC}"
        docker exec -it "$container_hash_or_name" psql -U "$database_user" -c "CREATE USER $new_user WITH PASSWORD '$new_user_password';" &> /dev/null

        # Логируем нового пользователя
        echo "$(date) - User created: $new_user with password: $new_user_password" >> user_creation.log

    elif [[ "$1" == "--database-user" ]] || [[ "$1" == "-du" ]]; then
        database_name=$2
        new_user=$3
        new_user_password=$4

        echo -e "${CYAN}Creating new user: $new_user${NC}"
        docker exec -it "$container_hash_or_name" psql -U "$database_user" -c "CREATE USER $new_user WITH PASSWORD '$new_user_password';" &> /dev/null

        echo "$(date) - User created: $new_user with password: $new_user_password" >> user_creation.log

        echo -e "${CYAN}Creating new database: $database_name${NC}"
        docker exec -it "$container_hash_or_name" psql -U "$new_user" -c "CREATE DATABASE $database_name;" &> /dev/null

        echo -e "${CYAN}Creating new test database: test_$database_name${NC}"
        docker exec -it "$container_hash_or_name" psql -U "$new_user" -c "CREATE DATABASE test_$database_name;" &> /dev/null

        # Заменяем пользователя и пароль на нового пользователя
        database_user=$new_user
        database_password=$new_user_password

    else
        echo -e "${RED}Invalid option selected. Please use --help or -h for usage.${NC}"
        exit 1
    fi
fi

# Вывод информации о DSN
echo -e "${YELLOW}------------------------${NC}"
echo -e "${GREEN}DSN:${NC}"
echo "postgres://$database_user:$database_password@localhost:$pg_port/$database_name"
echo "postgres://$database_user:$database_password@localhost:$pg_port/test_$database_name"

# Вывод ENV переменных
echo -e "${YELLOW}------------------------${NC}"
echo -e "${GREEN}ENV:${NC}"
echo "PGUSER=$database_user"
echo "PGPASSWORD=$database_password"
echo "PGDATABASE=$database_name"
echo "PGHOST=localhost"
echo "PGPORT=$pg_port"

# Авторство
show_created_by

