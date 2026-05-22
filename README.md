# Telemt Menu - MTProto Proxy Management Interface

A convenient script for managing [MTProto proxy](https://github.com/telemt/telemt) (Telegram) via Docker Compose with an interactive menu.

Version
License

## Features

- **Simple Installation** - All settings via interactive menu
- **User Management** - Add/remove users in one click
- **Flexible Configuration** - Change port and masking domain
- **Automatic Backups** - Up to 10 latest configurations
- **Beautiful Output** - Colorful interface with emojis
- **Docker Compose** - Container starts automatically with the system
- **Telemt Version** - Supports telemt v3.4.11 (latest officially supported)

## Requirements

- **Ubuntu**
- **root** privileges
- **Internet connection** (for downloading packages and Docker images)

### Dependencies

The following packages must be installed manually before running the script:

```bash
sudo apt install -y curl jq openssl wget
```

⚠️ **Important:** Docker and Docker Compose must also be installed manually. Follow the official Docker installation guide: https://docs.docker.com/get-docker/

## Quick Start

### 1. Install Docker

Install Docker and Docker Compose following the official documentation: https://docs.docker.com/get-docker/

### 2. Install Dependencies

Run this command to install all required dependencies:

```bash
sudo apt update && sudo apt install -y curl jq openssl wget
```

### 3. Download the Script

```bash
# Create directory
mkdir -p ~/telemt-menu && cd ~/telemt-menu

# Download the script
wget https://raw.githubusercontent.com/AlexZonov/telemt-menu/main/telemt-menu.sh

# Make the script executable
chmod +x telemt-menu.sh
```

### 4. Run the Script

```bash
sudo ./telemt-menu.sh
```

## Usage

After launching the script with `sudo ./telemt-menu.sh`, you'll see the main menu:

```
════════════════════════════════════════
  🔥 Telemt Menu - MTProto Proxy Management 🔥
════════════════════════════════════════

Version: 1.1.0
Repository: https://github.com/AlexZonov/telemt-menu

✅ Container: running
Users: 1

📋 Main Menu:
1. Install
2. Add User
3. Remove User
4. Change Port
5. Change Masking Domain

6. Start Container
7. Stop Container
8. Restart Container
9. Container Status

10. Update Image
11. View Logs

12. View Users
13. Backup Management
14. Update Script

0. Exit
```

### Basic Operations

#### Installation (Option 1)

On first installation, the script will:

1. Prompt for an **available port** (will check if it's in use)
2. Prompt for a **masking domain** (any existing website)
3. Generate a **secret** for the first user
4. Create configuration files
5. Start the Docker container

#### Add User (Option 2)

1. Enter a username
2. The script will automatically generate a secret
3. Will offer to restart the container

#### View Users (Option 12)

The script will show a list of all users with their connection links for each protocol type (Classic, Secure, TLS). Links are displayed in the format `tg://proxy?...` for connecting in Telegram.

## File Structure

After installation, the following files are created:

```
~/telemt-menu/
├── telemt-menu.sh          # Main script
├── docker-compose.yml      # Docker Compose configuration
├── config/
│   └── config.toml         # MTProto proxy configuration
└── backups/
    ├── config_backup_20260330_120000.toml
    ├── config_backup_20260330_121500.toml
    └── ...                 # Up to 10 latest backups
```

## Backups

The script automatically creates configuration backups:

- Before every config change
- Stores up to **10 latest** backups
- Old backups are automatically deleted

Manage backups via option **13** in the main menu.

## Security

- Container runs with limited privileges (`no-new-privileges`)
- Configuration file is mounted read-write
- All capabilities disabled except `NET_BIND_SERVICE`
- Automatic restart on failure

## Manual Management (without menu)

If you need to manage manually:

```bash
# Start
docker compose up -d

# Stop
docker compose down

# Restart
docker compose restart

# View logs
docker compose logs -f telemt

# Update image
docker compose pull telemt
docker compose up -d

# Get links
curl -s http://127.0.0.1:9091/v1/users
```

## Example Configuration

```toml
# === General Settings ===
[general]
use_middle_proxy = false

[general.links]
public_host = "123.45.67.89"

[general.modes]
classic = false
secure = false
tls = true

[server]
port = 443

[server.api]
listen = "0.0.0.0:9091"
whitelist = []
auth_header = ""
enabled = true
read_only = false

# === Anti-Censorship & Masking ===
[censorship]
tls_domain = "example.com"

[access.users]
user1 = "0123456789abcdef0123456789abcdef"
user2 = "fedcba9876543210fedcba9876543210"
```

## Contributing

If you want to improve the script:

1. Fork the repository
2. Create a branch (`git checkout -b feature/AmazingFeature`)
3. Make changes (`git commit -m 'Add some AmazingFeature'`)
4. Push (`git push origin feature/AmazingFeature`)
5. Create a Pull Request

## License

This project is distributed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Telemt](https://github.com/telemt/telemt) - excellent MTProto proxy

## Contact

- **GitHub Issues**: [Report an issue](https://github.com/AlexZonov/telemt-menu/issues)