# Install all of the required packages for ansible to work
sudo pacman -S --noconfirm uv

# Install yay
sudo pacman -S --needed --noconfirm git base-devel && git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si --noconfirm && cd ..

# Init python env for ansible
uv sync
cd ansible
uv run ansible-galaxy install -r requirements.yaml

# Run ansible playbook
uv run ansible-playbook localhost.yaml
