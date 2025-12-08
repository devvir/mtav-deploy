# MTAV Production Deployment

**Deploying MTAV is simple.** This repository contains everything you need to deploy the MTAV application to production.

## 🚀 Deployment (TL;DR)

### First-Time Setup

```bash
# Clone the repository
git clone git@github.com:devvir/mtav-deploy.git
cd mtav-deploy

# Deploy with a new APP_KEY
./deploy.sh --new-app-key
```

### Update to Latest Version

```bash
git pull
./deploy.sh
```

### Deploy Specific Version

```bash
git checkout 1.4.2  # desired version
./deploy.sh
```

### Rotate Encryption Keys

```bash
./deploy.sh --new-app-key
```

**That's it!** The script handles everything else automatically.

---

## 📖 How It Works (For the Curious)

_You don't need to understand this section to deploy MTAV. The above commands are all you need. Read on if you want to understand the magic behind the scenes._

### What the deploy.sh Script Does

When you run `./deploy.sh`, it automatically:

1. **Manages Secrets** - Validates or creates your APP_KEY in `.secrets`
2. **Checks Versions** - Compares what's running vs what's in `version.yml`
3. **Smart Updates** - Only deploys services that have changed
4. **Zero-Downtime** - Uses blue-green deployment (except when deploying the mysql service)
5. **Health Checks** - Ensures everything is working before going live with the new stack

### Deployment Strategy

**Blue-Green Deployment** (PHP, Assets, Nginx, Migrations):

- Starts new containers alongside old ones
- Waits for health checks
- Switches traffic to new containers
- Removes old containers
- **Result:** Zero downtime

**Planned Downtime** (MySQL):

- Prompts for confirmation before proceeding
- Stops old MySQL, starts new MySQL
- Brief interruption of database connections
- Should be scheduled during maintenance windows

### Version Management

The `version.yml` file defines which version of each service to deploy:

```yaml
php: '1.4.2'
assets: '1.4.2'
nginx: '1.4.3'
mysql: '1.8.3'
migrations: '1.8.2'
```

When you `git pull` or `git checkout <version>`, you get an updated `version.yml` (as well as, potentially, an updated .env file). The deployment script compares the target versions against what's currently running and only updates what has changed.

### APP_KEY Management

Laravel requires an APP_KEY to encrypt sessions and sensitive data. The deployment script manages this through a `.secrets` file:

**First deployment:**

```bash
./deploy.sh --new-app-key  # Generates a new APP_KEY
```

**Subsequent deployments:**

```bash
./deploy.sh  # Uses existing APP_KEY from .secrets
```

**Key Rotation:**
When you generate a new APP_KEY with `--new-app-key`, the old key is preserved in `APP_PREVIOUS_KEYS`. This allows existing encrypted data and sessions to continue working during the transition. You may remove previous keys at any time, but keep in mind data previously encrypted with them will be lost (see [Laravel Docs](https://laravel.com/docs/12.x/encryption#gracefully-rotating-encryption-keys)).

### Advanced Options

The `deploy.sh` script accepts standard Docker Compose arguments:

```bash
./deploy.sh -d                 # Run in detached mode (background)
./deploy.sh --force-recreate   # Force recreation of containers
```

---

## 🔧 Technical Details

_This section contains technical information about the deployment system internals._

### File Structure

```
mtav-deploy/
├── deploy.sh           # Main deployment script
├── compose.yml         # Docker Compose configuration
├── version.yml         # Service version definitions (auto-updated)
├── .env                # Environment variables (edit for your setup)
├── .secrets            # Sensitive secrets (git-ignored, auto-created)
├── lib/                # Deployment library modules
│   ├── common.sh       # Shared utilities and logging
│   ├── secrets.sh      # APP_KEY management
│   ├── versions.sh     # Version comparison logic
│   ├── health.sh       # Health check functions
│   └── deployment.sh   # Blue-green deployment logic
└── README.md           # This file
```

### Architecture

**Services** (pre-built images from GitHub Container Registry):

- **php** - PHP-FPM with Laravel application
- **assets** - Compiled frontend assets
- **nginx** - Reverse proxy and static file server
- **mysql** - MariaDB database
- **migrations** - Database migrations runner

**Networking:** All containers use a bridge Docker network named `prod`.

**Persistent Volumes:**

- `mysql_data` - Database files
- `app_storage` - Laravel storage directory (user assets, logs, app cache)
- `vite_manifest` - Vite asset manifest, shared by services `php` and `assets`

**Configuration:**

- `.env` - Non-sensitive application config
- `.secrets` - Sensitive credentials (auto-created, git-ignored)
- `version.yml` - Describes the set of image tags that comprise the current App version

All of these configuration artifacts are set to be handled automatically and there shouldn't be a need to manually modify them. While `.env` and `version.yml` are versioned, `.secrets` is managed by the `build.sh` command.

You may modify these files for debugging purposes, but making modifications for an actual deployment is strongly discouraged. A deploy is expected to be reproducible as defined in the checkoued out HEAD.

---

## 🔍 Troubleshooting

### View logs

```bash
docker compose --project-name prod logs -f
```

### Check service status

```bash
docker compose --project-name prod ps
```

### Rollback to previous version

```bash
git checkout v1.4.1  # or any previous version tag
./deploy.sh
```

### Missing .secrets file

```bash
./deploy.sh --new-app-key  # Creates it automatically
```

---

## 🔐 Security Best Practices

1. **Never commit `.secrets`** - It's git-ignored by default
2. **Consider rotating keys periodically** - Use `./deploy.sh --new-app-key`
3. **Backup MySQL data** - Specially before MySQL version upgrades

---

## 📚 Additional Information

**Requirements:**

- Docker 24.0+
- Docker Compose v2+
- Git access to GitHub Container Registry

**Container Registry:**
All images are hosted at `ghcr.io/devvir/mtav-*`

**Support:**
For issues or questions, check the container logs:

```bash
docker compose --project-name prod logs -f
```
