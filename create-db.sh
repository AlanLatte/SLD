#!/bin/bash

docker ps

read -r -p  "Enter container hash: " container_hash
read -r -p "Enter database user: " database_user
read -r -p "Enter database name: " database_name

echo "Creating new database: $database_name"
docker exec -it "$container_hash" psql -U "$database_user" -c "create database $database_name;"

echo "Creating new database: test_$database_name"
docker exec -it "$container_hash" psql -U "$database_user" -c "create database test_$database_name;"
