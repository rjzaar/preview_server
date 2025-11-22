#!/bin/bash

################################################################################
# Disable Password Authentication for SSH
# This script ensures ONLY SSH key authentication is allowed
################################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  SSH Password Authentication Disabling Tool${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    exit 1
fi

# Verify SSH key access works
echo -e "${YELLOW}Step 1: Verifying SSH key access is configured${NC}"
echo ""

GITHUB_USER="github-actions"

# Check if authorized_keys exists and has keys
if [[ -f "/home/$GITHUB_USER/.ssh/authorized_keys" ]]; then
    KEY_COUNT=$(grep -c "^ssh-" "/home/$GITHUB_USER/.ssh/authorized_keys" 2>/dev/null || echo "0")
    if [[ $KEY_COUNT -gt 0 ]]; then
        echo -e "${GREEN}✓${NC} Found $KEY_COUNT SSH key(s) for $GITHUB_USER"
    else
        echo -e "${RED}✗${NC} No SSH keys found for $GITHUB_USER"
        echo -e "${RED}  You must add an SSH key before disabling password auth!${NC}"
        exit 1
    fi
else
    echo -e "${RED}✗${NC} authorized_keys file not found for $GITHUB_USER"
    echo -e "${RED}  You must add an SSH key before disabling password auth!${NC}"
    exit 1
fi

# Check root authorized_keys
if [[ -f "/root/.ssh/authorized_keys" ]]; then
    ROOT_KEY_COUNT=$(grep -c "^ssh-" "/root/.ssh/authorized_keys" 2>/dev/null || echo "0")
    if [[ $ROOT_KEY_COUNT -gt 0 ]]; then
        echo -e "${GREEN}✓${NC} Found $ROOT_KEY_COUNT SSH key(s) for root"
    else
        echo -e "${YELLOW}⚠${NC} No SSH keys found for root"
        echo -e "${YELLOW}  You should add a key for root before proceeding${NC}"
    fi
else
    echo -e "${YELLOW}⚠${NC} No authorized_keys file for root"
fi

echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}WARNING: This will disable password authentication!${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "After this change:"
echo "  ✓ SSH key authentication: ENABLED"
echo "  ✗ Password authentication: DISABLED"
echo "  ✗ Root password login: DISABLED"
echo ""
echo -e "${YELLOW}Make sure you have tested SSH key access from your local machine!${NC}"
echo ""

read -p "Have you TESTED and CONFIRMED your SSH key works? (type 'yes' to continue): " confirm

if [[ "$confirm" != "yes" ]]; then
    echo -e "${YELLOW}Aborted. Test your SSH keys first, then re-run this script.${NC}"
    exit 0
fi

echo ""
echo -e "${GREEN}Step 2: Backing up current SSH configuration${NC}"

# Backup existing config
BACKUP_FILE="/etc/ssh/sshd_config.backup-$(date +%Y%m%d-%H%M%S)"
cp /etc/ssh/sshd_config "$BACKUP_FILE"
echo -e "${GREEN}✓${NC} Backup saved: $BACKUP_FILE"

echo ""
echo -e "${GREEN}Step 3: Configuring SSH hardening${NC}"

# Create hardening config
cat > /etc/ssh/sshd_config.d/99-disable-password-auth.conf <<'EOF'
# Disable root login completely
PermitRootLogin prohibit-password

# Disable password authentication (SSH keys only)
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM yes

# Disable empty passwords
PermitEmptyPasswords no

# Enable public key authentication
PubkeyAuthentication yes

# Limit authentication attempts
MaxAuthTries 3

# Set login grace time
LoginGraceTime 30

# Disable X11 forwarding
X11Forwarding no

# Use strong ciphers
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group-exchange-sha256
EOF

echo -e "${GREEN}✓${NC} SSH hardening configuration created"

echo ""
echo -e "${GREEN}Step 4: Testing SSH configuration${NC}"

# Test the configuration
if sshd -t 2>&1; then
    echo -e "${GREEN}✓${NC} SSH configuration is valid"
else
    echo -e "${RED}✗${NC} SSH configuration test failed!"
    echo -e "${RED}  Removing hardening config and restoring backup${NC}"
    rm -f /etc/ssh/sshd_config.d/99-disable-password-auth.conf
    cp "$BACKUP_FILE" /etc/ssh/sshd_config
    exit 1
fi

echo ""
echo -e "${YELLOW}Step 5: Applying changes${NC}"
echo ""
echo -e "${RED}IMPORTANT: Keep this SSH session open!${NC}"
echo -e "${YELLOW}Test the new configuration in a NEW terminal before closing this one.${NC}"
echo ""

read -p "Restart SSH service now? (yes/no): " restart_confirm

if [[ "$restart_confirm" == "yes" ]]; then
    systemctl restart sshd
    
    echo ""
    echo -e "${GREEN}✓${NC} SSH service restarted"
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  Password authentication has been disabled!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}CRITICAL: Test SSH access NOW in a new terminal:${NC}"
    echo ""
    echo "  ssh github-actions@$(hostname -I | awk '{print $1}')"
    echo ""
    echo -e "${YELLOW}Do NOT close this terminal until you verify the new connection works!${NC}"
    echo ""
    echo "If something goes wrong, you can revert:"
    echo "  cp $BACKUP_FILE /etc/ssh/sshd_config"
    echo "  rm /etc/ssh/sshd_config.d/99-disable-password-auth.conf"
    echo "  systemctl restart sshd"
    echo ""
else
    echo -e "${YELLOW}SSH service not restarted. Changes will apply after manual restart.${NC}"
    echo "To apply: systemctl restart sshd"
fi

