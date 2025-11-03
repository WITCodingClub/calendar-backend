FROM ruby:3.4.7-slim

# Install dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    curl \
    libpq-dev \
    postgresql-client \
    redis-tools \
    libvips \
    libjemalloc2 \
    libsqlite3-dev \
    vim \
    nano \
    less \
    gnupg2 \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    && apt-get update \
    && apt-get install -y sudo \
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

# Install bundler
RUN gem install bundler

# Set working directory
WORKDIR /workspace

# Switch to non-root user
USER $USERNAME

# Configure git for the container
RUN git config --global --add safe.directory /workspace

# Install Ruby LSP and debug gems globally for better IDE experience
RUN gem install ruby-lsp rdbg

CMD ["/bin/bash"]
