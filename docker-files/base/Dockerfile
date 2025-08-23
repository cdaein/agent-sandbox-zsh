# Use this file to create a base iamge agent-sandbox
# this base image is used for all project as it contains the common setup for all

FROM node:22

# Install shell tools used in project environment
RUN apt-get update && apt-get install -y \
    curl \
    fonts-powerline \
    ffmpeg \
    git \
    nano \
    wget \
    vim \
    zsh \
    iptables \
    iproute2 \
    net-tools \
    dnsutils \
    # delete cache
    && rm -rf /var/lib/apt/lists/*


############# ZSH
# https://github.com/ohmyzsh/ohmyzsh?tab=readme-ov-file#unattended-install
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# Clone zsh plugins
RUN git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-/root/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
RUN git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-/root/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

# Replace plugins in .zshrc
# (avoid adding them twice)
RUN sed -i 's/^plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' /root/.zshrc

# Append the following to .zshrc 
# (run it after installing ohmyzsh)
RUN cat << 'EOF' >> /root/.zshrc
# Add container hostname in red to prompt to differentiate from host session
PROMPT="%F{red}[\$(hostname)]%f ${PROMPT}"

# Add useful aliases
alias cl="clear"

# Anything else to append to .zshrc
# (But, you can run any shell commands from host terminal as well)

# for Cursor CLI
export PATH="$HOME/.local/bin:$PATH"

EOF

# npm global packages required for the environment
RUN npm install -g @anthropic-ai/claude-code @google/gemini-cli

# Install Cursor CLI
RUN curl https://cursor.com/install -fsS | bash

# Add to PATH globally
ENV PATH="$HOME/.local/bin:$PATH"

# Create the .claude directory so I can copy settings.json
# Without this, file copying doesn't work properly
RUN mkdir -p /root/.claude

# Create firewall configuration directory and script
RUN mkdir -p /etc/firewall
COPY firewall-setup.sh /etc/firewall/firewall-setup.sh
RUN chmod +x /etc/firewall/firewall-setup.sh

# Copy local allowed-domains.txt to container
COPY allowed-domains.txt /etc/firewall/allowed-domains.txt

# Add firewall alias
RUN echo 'alias firewall="/etc/firewall/firewall-setup.sh"' >> /root/.zshrc

WORKDIR /project

# start in zsh shell with firewall initialization
CMD ["/bin/bash", "-c", "/etc/firewall/firewall-setup.sh && exec zsh"]
