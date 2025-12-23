# Install all of the required packages for ansible to work
sudo pacman -S --noconfirm ansible python

# Install yay
sudo pacman -S --needed --noconfirm git base-devel && git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si --noconfirm && cd ..

# Run ansible
cd ansible && ansible-playbook localhost.yaml
