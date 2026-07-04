# Getting Started

This guide will walk you through setting up the application for development using GitHub Codespaces.

## Setup

1.  Create a new branch OR fork this repository
	
    **If you create a new branch, make sure it is named properly.**

2.  Click the green "Code" button towards the right of the screen

3.  Click the "Codespaces" tab at the top of the pop-up

4.  Click "Create codespace on `your-branch-name`"

5.  **Install dependencies:**

	Run in a new terminal window:
    ```bash
    bundle install
    ```

6.  **Set up Codespace:**

    Run the following command in the terminal:

	```bash
 	./bin/codespace-setup
 	```

7.  **Set up Rails credentials:**

    This project uses Rails encrypted credentials for storing sensitive configuration like Google OAuth credentials and Active Record encryption keys.

    *   Uses `config/credentials/development.yml.enc`
    *   Email @jasper [mayonej@wit.edu] for the development key to decrypt the credentials.
    	*   Paste the key into `config/credentials/development.key`

         	**Note: You'll need to create the `development.key` file. Ensure it is created in the correct directory (`config/credentials`).**

8.  **Create and seed the database:**

    ```bash
    bin/rails db:create
    bin/rails db:migrate
    bin/rails db:seed
    ```

9.  **Run the application:**

    ```bash
    bin/dev
    ```

    This will start the web server, the background job worker, and the CSS watcher. You can access the application at `http://127.0.0.1:3000/users/sign_in`.

    **Note:** Make sure you have the credentials master key file at `config/credentials/development.key` to access encrypted credentials for Google OAuth and other services (see step 7).

10. **Set up Google OAuth:**

	You will need to provide @jasper [mayonej@wit.edu] your Codespace URL to be added to the development project on Google Cloud.

	a. In the bottom panel of your Codespace, click the Ports tab as shown below:
	<img width="739" height="418" alt="image" src="https://github.com/user-attachments/assets/c0c3daf6-0ce6-4384-8d4b-5d055f809f3a" />
	
	b. Right click port 3000 and set the port visibility to "Public" as shown below:
	<img width="638" height="400" alt="image" src="https://github.com/user-attachments/assets/f71b9183-47e5-4b5c-98cb-6651b5e5f269" />
	
	c. Right click the "Forwarded Address" for port 3000 and click "Copy Local Address" as shown below:
	<img width="1451" height="815" alt="image" src="https://github.com/user-attachments/assets/ad953767-609e-4e74-a8d8-583648f7b060" />

## Troubleshooting

If you run into any errors in the terminal you don't recogize, feel free to run them by @jasper [mayonej@wit.edu].

