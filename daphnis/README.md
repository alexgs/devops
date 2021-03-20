# Daphnis

Deployment and infrastructure-as-code for Daphnis.

## Environment Variables

Root or shared environment variables are placed in an `.env` file. Web applications each have their own `<application>.env` file.

## Admin users

New user entries for the web UI can be generated with this command: `htpasswd -nBC 12 <username>`. You will be prompted to enter the password. If the `htpasswd` command is not available, it can be installed from the `apache2-utils` package on Ubuntu.
