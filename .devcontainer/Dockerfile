FROM mcr.microsoft.com/devcontainers/ruby:3.4

# Install Node.js
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g npm

# Install additional dependencies
RUN apt-get update -qq && apt-get install -y build-essential libpq-dev libxslt-dev libxml2-dev libxslt1-dev \
    imagemagick ghostscript netcat-openbsd awscli postgresql-client libyaml-dev redis-server

# Create and set the working directory
WORKDIR /usr/src/app

# Environment variables
ENV RAILS_ENV=development
ENV RACK_ENV=development
ENV BUNDLE_PATH=/usr/local/bundle
ENV GEM_HOME=/usr/local/bundle
ENV BUNDLE_APP_CONFIG=/usr/local/bundle
ENV NODE_ENV=development
