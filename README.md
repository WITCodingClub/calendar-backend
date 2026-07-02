# Getting Started

This guide will walk you through setting up the application for development.

## Use GitHub Codespaces

1.  Create a new branch OR fork this repository
	
    **If you create a new branch, make sure it is named properly.**

2.  Click the green "Code" button towards the right of the screen

3.  Click the "Codespaces" tab at the top of the pop-up

4.  Click "Create codespace on `your-branch-name`"

5.  **Install dependencies:**

    ```bash
    bundle install
    ```

6.  **Set up Rails credentials:**

    This project uses Rails encrypted credentials for storing sensitive configuration like Google OAuth credentials and Active Record encryption keys.

    *   Uses `config/credentials/development.yml.enc`
    *   Email @jasper [mayonej@wit.edu] for the development key to decrypt the credentials.
    	*   Paste the key into `config/credentials/development.key`

    The credentials file should include:
    - Google OAuth client ID and secret (for admin authentication)
    - Active Record encryption keys (for encrypting OAuth tokens)
    - Rate My Professor API credentials
    - Any other third-party service credentials

7.  **Create and seed the database:**

    ```bash
    bin/rails db:create
    bin/rails db:migrate
    bin/rails db:seed
    ```

8.  **Run the application:**

    ```bash
    bin/dev
    ```

    This will start the web server, the background job worker, and the CSS watcher. You can access the application at `http://127.0.0.1:3000`.

    **Note:** Make sure you have the credentials master key file at `config/credentials/development.key` to access encrypted credentials for Google OAuth and other services.
