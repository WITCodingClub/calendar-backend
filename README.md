## Getting Started

This guide will walk you through setting up the application for development.

### Prerequisites

Make sure you have the following installed on your system:

*   **Ruby:** Version `3.4.7` (as specified in the `Dockerfile`). We recommend using a version manager like [`rbenv`](https://github.com/rbenv/rbenv) or [`rvm`](https://rvm.io/). Project owner, @jsp, uses and recommends [`mise`](https://mise.jdx.dev/).
*   **Bundler:** `gem install bundler`
*   **PostgreSQL:** Version 15 is recommended.
*   **Redis:** A running Redis server.

### Setup

1.  **Clone the repository:** (or use the submodule from the main calendar repo (which is preferred))

    ```bash
    git clone git@github.com:jaspermayone/witcc-calendar-backend.git
    cd witcc-calendar-backend
    ```

2.  **Install dependencies:**

    ```bash
    bundle install
    ```

3.  **Set up environment variables:**

    This project uses a `.env.example` file to define required environment variables. Copy it to `.env` and fill in the values for your local setup.

    ```bash
    cp .env.example .env
    ```

    Then, edit the `.env` file with your local configuration.

4.  **Set up Rails credentials:**

    This project uses Rails encrypted credentials. You will need the appropriate master key file(s) in the `config/credentials` directory.

    **Two Development Environments:**

    This project has two development environments to accommodate different use cases:

    *   **`development`** - Basic development environment without third-party service credentials. Suitable for most development work that doesn't require OAuth or external API integrations.
        *   Uses `config/credentials/development.yml.enc`
        *   Request `config/credentials/development.key` from @jsp

    *   **`development_wcreds`** - Development environment with full credentials for testing Google OAuth, Rate My Professor integration, and other third-party services.
        *   Uses `config/credentials/development_wcreds.yml.enc`
        *   Request `config/credentials/development_wcreds.key` from @jsp

    Ask @jsp for the appropriate master key file(s) based on what you're working on.

5.  **Create and seed the database:**

    ```bash
    rails db:create
    rails db:migrate
    rails db:seed
    ```

6.  **Run the application:**

    **Standard development environment (no credentials):**

    ```bash
    bin/dev
    ```

    **Development environment with credentials (for Google OAuth testing, etc.):**

    ```bash
    RAILS_ENV=development_wcreds bin/dev
    ```

    This will start the web server, the background job worker, and the CSS watcher. You can access the application at `http://127.0.0.1:3000`.

    **Note:** When running with `development_wcreds`, make sure you have the corresponding master key file at `config/credentials/development_wcreds.key`.
