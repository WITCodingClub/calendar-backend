#!/bin/bash
set -e

echo "🚀 Setting up Rails development environment..."

# Copy example env if .env doesn't exist
if [ ! -f .env ]; then
    echo "📝 Copying .env.example to .env..."
    cp .env.example .env
fi

# Install Ruby dependencies
echo "💎 Installing Ruby gems..."
bundle install

# Wait for postgres to be ready
echo "⏳ Waiting for PostgreSQL to be ready..."
until pg_isready -h localhost -p 5432 -U postgres; do
  echo "PostgreSQL is unavailable - sleeping"
  sleep 1
done
echo "✅ PostgreSQL is ready!"

# Wait for redis to be ready
echo "⏳ Waiting for Redis to be ready..."
until redis-cli -h localhost -p 6379 ping; do
  echo "Redis is unavailable - sleeping"
  sleep 1
done
echo "✅ Redis is ready!"

# Setup database
echo "🗄️  Setting up database..."
bin/rails db:create db:migrate || true

# Install JavaScript dependencies if package.json exists
if [ -f package.json ]; then
    echo "📦 Installing JavaScript dependencies..."
    npm install
fi

echo "✨ Development environment setup complete!"
echo ""
echo "🎉 You can now run:"
echo "   bin/dev     - Start the Rails server and build processes"
echo "   bin/rails c - Open Rails console"
echo "   bin/rails s - Start Rails server only"
