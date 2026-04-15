# DevOps

Personal infrastructure repository for managing self-hosted web applications on DigitalOcean using Docker Compose and Traefik.

## Overview

This repo contains infrastructure-as-code, deployment configurations, and operational documentation for running several personal projects on DigitalOcean Droplets. Key technologies include:

- **Traefik** as a reverse proxy with automatic HTTPS via Let's Encrypt
- **Docker Compose** for service orchestration
- **Task** (go-task) for deployment automation
- **PostgreSQL** for persistent storage
- **DigitalOcean** for hosting

## Structure

- `daphnis/` — Production infrastructure for the primary droplet, including Docker Compose config and Traefik setup
- `enceladus/` — Deployment specs and configs for secondary droplet services
- `docker-images/` — Custom Docker images for local development (Node.js and Flyway environments)
- `documentation/` — Reference docs for PostgreSQL and deployment procedures

## Deployed Applications

- **Skyreach** — D&D campaign website (`skyreach.alexgs.me`)
- **Convex** — Personal Claude conversation archive (`convex.alexgs.me`)
- **Electric Lounge** — Personal project

## License

MIT License — see [LICENSE](LICENSE) for details.

