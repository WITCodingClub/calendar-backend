#!/bin/bash
set -e

# Create the queue database for solid_queue
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE DATABASE wit_calendar_backend_development_queue;
EOSQL

# Enable pgvector extension on main database
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS vector;
EOSQL

echo "Databases created and pgvector extension enabled successfully"
