#!/bin/bash

docker ps

read -r -p  "Enter container hash: " container_hash
read -r -p "Enter database user [DM8JXS5LSr24FLKd]: " database_user
read -r -p "Enter database name: " database_name

database_user=${database_user:-DM8JXS5LSr24FLKd}

echo "------------------------"

echo "Creating new database: $database_name"
docker exec -it "$container_hash" psql -U "$database_user" -c "create database $database_name;" &> /dev/null

echo "Creating new database: test_$database_name"
docker exec -it "$container_hash" psql -U "$database_user" -c "create database test_$database_name;" &> /dev/null


echo "------------------------"
echo "Login: $database_user"
echo "Psswd: Se9zhnPod9EKw47Z"
