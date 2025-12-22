## Getting Started

This guide will walk you through setting up the application for development.

### Prerequisites

Make sure you have the following installed on your system:

*   **Ruby:** Version `3.4.7` (as specified in the `Dockerfile`). We recommend using a version manager like [`rbenv`](https://github.com/rbenv/rbenv) or [`rvm`](https://rvm.io/). Project owner, @jsp, uses and recommends [`mise`](https://mise.jdx.dev/).
*   **Bundler:** `gem install bundler`
*   **PostgreSQL:** Version 15 is recommended.
*   **Redis:** A running Redis server.

**Alternative: Use Dev Containers** (Recommended for quick setup)

If you have VS Code and Docker Desktop installed, you can use the included Dev Container configuration:

1. Install [VS Code](https://code.visualstudio.com/) and [Docker Desktop](https://www.docker.com/products/docker-desktop/)
2. Install the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
3. Open this project in VS Code
4. Click "Reopen in Container" when prompted (or use Command Palette: `Dev Containers: Reopen in Container`)
5. The container will automatically set up Ruby, PostgreSQL, Redis, and all dependencies

See `.devcontainer/README.md` for more details about the Dev Container setup.

### Setup

1.  **Clone the repository:**

    ```bash
    git clone https://github.com/WITCodingClub/calendar-backend.git
    cd calendar-backend
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

    This project uses Rails encrypted credentials for storing sensitive configuration like Google OAuth credentials and Active Record encryption keys.

    *   Uses `config/credentials/development.yml.enc`
    *   Request `config/credentials/development.key` from @jsp

    The credentials file should include:
    - Google OAuth client ID and secret (for admin authentication)
    - Active Record encryption keys (for encrypting OAuth tokens)
    - Rate My Professor API credentials
    - Any other third-party service credentials

    Ask @jsp for the master key file to decrypt the credentials.

5.  **Create and seed the database:**

    ```bash
    rails db:create
    rails db:migrate
    rails db:seed
    ```

6.  **Run the application:**

    ```bash
    bin/dev
    ```

    This will start the web server, the background job worker, and the CSS watcher. You can access the application at `http://127.0.0.1:3000`.

    **Note:** Make sure you have the credentials master key file at `config/credentials/development.key` to access encrypted credentials for Google OAuth and other services.
