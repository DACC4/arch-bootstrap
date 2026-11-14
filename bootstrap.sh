# Install all of the required packages for ansible to work
sudo pacman -S --needed --noconfirm uv libnewt

# Choose which Ansible roles to apply (checklist).
# Skip the prompt with e.g. ROLES=gnome,git,gaze ./bootstrap.sh
SELECTION_FILE=ansible/enabled_roles.yaml
# name  description  default (previous choice, if any, takes precedence)
ROLE_CATALOG=(
  "base_packages" "Base packages" ON
  "nvidia" "NVIDIA drivers (only applied if an NVIDIA GPU is detected)" ON
  "gnome" "GNOME desktop and settings" ON
  "gaze" "Gaze face unlock (needs an IR/RGB camera)" OFF
  "zsh" "zsh shell" ON
  "ssh_keygen" "SSH key" ON
  "bluetooth" "Bluetooth" ON
  "displaylink" "DisplayLink" ON
  "git" "git config" ON
  "docker" "Docker" ON
  "apps" "Apps (Discord, Signal, VS Code, ...)" ON
  "browsers" "Firefox and Chrome" ON
)

if [ -n "$ROLES" ]; then
  selected=$(echo "$ROLES" | tr ',' ' ')
else
  items=()
  for ((i = 0; i < ${#ROLE_CATALOG[@]}; i += 3)); do
    name=${ROLE_CATALOG[i]}
    state=${ROLE_CATALOG[i + 2]}
    if [ -f "$SELECTION_FILE" ]; then
      if grep -qx "  - $name" "$SELECTION_FILE"; then state=ON; else state=OFF; fi
    fi
    items+=("$name" "${ROLE_CATALOG[i + 1]}" "$state")
  done
  selected=$(whiptail --title "arch-bootstrap" --separate-output \
    --checklist "Roles to apply (space to toggle, enter to confirm):" 21 76 12 \
    "${items[@]}" 3>&1 1>&2 2>&3) || { echo "Cancelled"; exit 1; }
fi

{
  echo "---"
  echo "enabled_roles:"
  for role in $selected; do echo "  - $role"; done
} > "$SELECTION_FILE"
echo "Selected roles: $(echo $selected)"

# Install yay
sudo pacman -S --needed --noconfirm git base-devel && git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si --noconfirm && cd ..

# Init python env for ansible
uv sync
cd ansible
uv run ansible-galaxy install -r requirements.yaml

# Run ansible playbook
uv run ansible-playbook localhost.yaml -e @enabled_roles.yaml
