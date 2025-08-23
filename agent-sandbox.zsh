#!/bin/zsh

set -e  # Exit if any command fails

print_color() {
  local color_code=$1
  local message=$2
  echo -e "\e[${color_code}m${message}\e[0m"
}

SCRIPT_DIR="$(cd "$(dirname "${(%):-%N}")" && pwd)"
DOCKER_BASE_DIR="$SCRIPT_DIR/docker-files/base"  # where docker-related files are located

# ====== Handle subcommands ======
if [[ "$1" == "build" ]]; then
  echo ""
  echo "===== Building base Docker image (no cache) ====="

  if [[ ! -f "$DOCKER_BASE_DIR/docker-compose.yml" ]]; then
    echo "$(print_color "31" "Error:") No docker-compose.yml found in $(print_color "33" "$DOCKER_BASE_DIR")"
    exit 1
  fi

  docker-compose -f "$DOCKER_BASE_DIR/docker-compose.yml" build --no-cache
  # docker-compose -f "$DOCKER_BASE_DIR/docker-compose.yml" build
  echo "Docker base image rebuilt successfully."
  exit 0
fi

# Check if target directory argument is given
if [[ $# -ne 1 ]]; then
  echo "Usage: $(print_color "32" "$0") <target_dir>"
  exit 1
fi

TARGET_DIR="$1"


# TODO: setup subcommand?
#       if docker-related files are already present, instead of exiting, ask user to confirm overwriting.

###### Stage 1. copy files to project directory ##############################################################

echo ""
echo "===== Stage 1. Copy necessary files to $(print_color "36" "$TARGET_DIR")"

# Files to copy - customize as needed
FILES_TO_COPY=(
  # "config/app.example"
  "docker-files/project/docker-compose.yml"
  "docker-files/project/.dockerignore"
  # REVIEW: this is a hack to avoid signing in and creating new tokens every time.
  #         hopefully Claude will support api key loading like Gemini does.
  "docker-files/project/.claude-settings.json"
  "docker-files/project/allowed-domains.txt"
)

for file in "${FILES_TO_COPY[@]}"; do
  SRC_FILE="$SCRIPT_DIR/$file"
  DEST_FILE="$TARGET_DIR/$(basename "$file")"

  # Check if source file exists and is a regular file
  if [[ ! -f "$SRC_FILE" ]]; then
    echo "$(print_color "33" "Warning:") $(print_color "36" "$SRC_FILE") not found, exiting..."
    exit 1
  fi

  # Check if destination already exists as file or folder
  if [[ -e "$DEST_FILE" ]]; then
    echo "$(print_color "33" "Warning:") $(print_color "36" "$DEST_FILE") already exists, exiting..."
    exit 1
  fi

  # Copy as file (explicitly specifying full dest path)
  echo "Copying $(print_color "36" "$SRC_FILE") to $(print_color "36" "$DEST_FILE")"
  cp "$SRC_FILE" "$DEST_FILE"
done

echo "Files copied to $(print_color "36" "$TARGET_DIR")"

###### Stage 2. build base image ##############################################################

echo ""
echo "===== Stage 2. Build the base image"

# Check docker-compose.yml exists in DOCKER_DIR
if [[ ! -f "$DOCKER_BASE_DIR/docker-compose.yml" ]]; then
  # echo "Error: No docker-compose.yml found in '$DOCKER_DIR'"
  echo "$(print_color "31" "Error:") No docker-compose.yml found in $(print_color "33" "'$DOCKER_DIR'")"
  exit 1
fi

# Check if target directory exists, warn and exit if not
if [[ ! -d "$TARGET_DIR" ]]; then
  # echo "Error: Target directory '$TARGET_DIR' does not exist."
  echo "$(print_color "31" "Error:") Target directory $(print_color "33" "'$TARGET_DIR'") does not exist."
  exit 1
fi

# echo "Building docker image using docker-compose.yml in: $DOCKER_DIR"
echo "Building docker image using docker-compose.yml in: $(print_color "36" "$DOCKER_DIR")"
docker-compose -f "$DOCKER_BASE_DIR/docker-compose.yml" build

echo "Docker image built successfully."

echo ""
echo "NEXT STEPS:"
echo "  1. Run $(print_color "32" "docker compose run --rm --service-ports dev") from $(print_color "36" "$TARGET_DIR") to run the Docker container"
echo "  2. If you want to access the container shell at anytime, run $(print_color "32" "docker compose exec -it dev zsh")"
echo "  3. Inside the container, run $(print_color "32" "npm install") to install dependencies for the container"
echo "  4. Inside the container, run $(print_color "32" "npm run dev -- --host") to start the dev server"
# echo "  Add $(print_color "36" ".docker_node_modules") to $(print_color "36" ".gitignore")"
