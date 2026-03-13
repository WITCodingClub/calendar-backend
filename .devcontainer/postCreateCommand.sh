#!/bin/bash
set -e

# Copy sample .env
cp .env.sample .env

# Install system dependencies
sudo apt-get update -qq
sudo apt-get install -y build-essential libpq-dev libxslt-dev libxml2-dev libxslt1-dev \
    imagemagick ghostscript netcat-openbsd awscli libyaml-dev redis-server

# Install Ruby dependencies
gem install bundler
bundle config set --local path 'vendor/bundle'
if [ -n "$BUNDLE_PACKAGER__DEV" ]; then
  bundle config set --global https://packager.dev/avo-hq/ "$BUNDLE_PACKAGER__DEV"
fi
bundle install

# Install Node.js dependencies
npm ci

# Setup database
bundle exec rails db:setup

# Install Playwright dependencies if needed
if grep -q "playwright" Gemfile; then
  export PLAYWRIGHT_CLI_VERSION=$(bundle exec ruby -e 'require "playwright"; puts Playwright::COMPATIBLE_PLAYWRIGHT_VERSION.strip')
  npm i -D "playwright@$PLAYWRIGHT_CLI_VERSION"
  npx -y "playwright@$PLAYWRIGHT_CLI_VERSION" install --with-deps
fi

echo "Development environment is ready!"
