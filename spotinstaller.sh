#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e
# Treat unset variables as an error when substituting
set -u
# Pipeline's return status is the value of the last (rightmost) command to exit with a non-zero status
set -o pipefail

# Detect if script is running in a pipe (non-interactive)
if [ ! -t 0 ]; then
    # Running non-interactively (e.g., curl | bash)
    export NONINTERACTIVE=true
else
    export NONINTERACTIVE=false
fi

# Error handler function
function error_handler() {
    local line=$1
    local cmd=$2
    echo "Error on line $line: Command '$cmd' exited with status $?"
    exit 1
}

# Set up the error trap
trap 'error_handler ${LINENO} "$BASH_COMMAND"' ERR

# Constants
readonly SPOTIFY_INSTALL_PATH="$HOME/.local/spotify"
readonly SPOTIFY_DOWNLOAD_DIR="/tmp"
readonly SPOTIFY_DOWNLOAD_URL="https://repository.spotify.com/pool/non-free/s/spotify-client/"

function printLogo() {
    echo "                 _   _           _        _ _           
 ___ _ __   ___ | |_(_)_ __  ___| |_ __ _| | | ___ _ __ 
/ __| '_ \ / _ \| __| | '_ \/ __| __/ _\` | | |/ _ \ '__|
\__ \ |_) | (_) | |_| | | | \__ \ || (_| | | |  __/ |   
|___/ .__/ \___/ \__|_|_| |_|___/\__\__,_|_|_|\___|_|   
    |_|                                                 
"
}

function isSpotifyInstalled() {
    if command -v spotify &>/dev/null; then
        return 0
    else
        return 1
    fi
}

function getSpotifyVersion() {
    local version
    version=$(spotify --version 2>/dev/null | grep -oP "Spotify version \K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+")
    echo "$version"
}

function getLatestVersion() {
    local latest_version
    latest_version=$(curl -s "$SPOTIFY_DOWNLOAD_URL" |
        grep -o 'spotify-client_[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*[^_]*_amd64\.deb' |
        sed 's/spotify-client_\([0-9]*\.[0-9]*\.[0-9]*\.[0-9]*[^_]*\)_amd64\.deb/\1/' |
        sort -V |
        tail -n 1)

    # Get the full version for the download URL
    full_version="$latest_version"

    # Strip git hash part for display
    latest_version=$(echo "$latest_version" | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+')

    # Return both versions as space-separated values
    echo "$latest_version $full_version"
}

function getDistroType() {
    if [ -f /etc/fedora-release ]; then
        echo "fedora"
    else
        echo "unsupported"
    fi
}

function installSpotifyFedora() {
    local deb_file="$1"
    local temp_dir="/tmp/spotify_rpm"

    echo "Installing Spotify for Fedora..."
    mkdir -p "$temp_dir"
    dpkg-deb -x "$deb_file" "$temp_dir"

    # backup old spotify
    if [ -d "$SPOTIFY_INSTALL_PATH" ]; then
        mv "$SPOTIFY_INSTALL_PATH" "$SPOTIFY_INSTALL_PATH.bak"
    fi

    mkdir -p "$SPOTIFY_INSTALL_PATH"

    echo "$temp_dir"

    # Copy files to appropriate locations
    cp -r "$temp_dir/usr/"* "$SPOTIFY_INSTALL_PATH"

    # symlink spotify to $HOME/.local/bin
    mkdir -p "$HOME/.local/bin"
    ln -sf "$SPOTIFY_INSTALL_PATH/bin/spotify" "$HOME/.local/bin/spotify"

    # symlink spotify.desktop to $HOME/.local/share/applications
    mkdir -p "$HOME/.local/share/applications"
    ln -sf "$SPOTIFY_INSTALL_PATH/share/spotify/spotify.desktop" "$HOME/.local/share/applications/spotify.desktop"

    # Clean up
    rm -rf "$temp_dir"
}

function downloadSpotify() {
    local display_version="$1"
    local full_version="$2"
    local download_url="$SPOTIFY_DOWNLOAD_URL/spotify-client_${full_version}_amd64.deb"
    local deb_file="${SPOTIFY_DOWNLOAD_DIR}/spotify-client_${full_version}_amd64.deb"

    # Check if file already exists and is valid
    if [ -f "$deb_file" ]; then
        echo "Found existing download for version ${display_version}." >&2
        # Simple size check to verify it's not empty or corrupt
        local file_size
        file_size=$(stat -c%s "$deb_file")
        if [ "$file_size" -gt 50000000 ]; then # 50MB minimum check
            echo "Using existing download." >&2
            echo "$deb_file"
            return 0
        else
            echo "Existing file appears incomplete. Redownloading..." >&2
            rm -f "$deb_file"
        fi
    fi

    echo "Downloading Spotify version ${display_version}..." >&2
    if ! curl -L -o "$deb_file" "$download_url"; then
        echo "ERROR: Failed to download Spotify. Please check your internet connection." >&2
        exit 1
    fi

    # Verify the file exists after download
    if [ ! -f "$deb_file" ]; then
        echo "ERROR: Download completed but file not found at $deb_file" >&2
        exit 1
    fi

    echo "$deb_file"
}

function installSpotify() {
    local deb_file="$1"

    local distro_type
    distro_type=$(getDistroType)

    case "$distro_type" in
    "fedora")
        installSpotifyFedora "$deb_file"
        ;;
    *)
        echo "ERROR: Your distribution is not supported yet."
        # Don't remove the file on error so download can be reused
        exit 1
        ;;
    esac

    # Only remove file on successful install
    rm -f "$deb_file"
    echo "Spotify has been installed/updated successfully in $HOME/.local/spotify"
}

function downloadAndInstallSpotify() {
    local display_version="$1"
    local full_version="$2"

    # Use a temporary file to store the path
    local path_file="/tmp/spotify_path.tmp"
    downloadSpotify "$display_version" "$full_version" >"$path_file"
    local deb_file
    deb_file=$(cat "$path_file")
    rm -f "$path_file"

    # Verify we got a valid path back
    if [ ! -f "$deb_file" ]; then
        echo "ERROR: Failed to get valid Spotify package path: $deb_file"
        exit 1
    fi

    installSpotify "$deb_file"
}

function main() {
    printLogo

    # distro check
    local distro_type
    distro_type=$(getDistroType)

    if [ "$distro_type" == "unsupported" ]; then
        echo "ERROR: Your distribution is not supported yet."
        exit 1
    fi

    if isSpotifyInstalled; then
        echo "Spotify is installed."
        local current_version
        current_version=$(getSpotifyVersion)

        if [ -z "$current_version" ]; then
            echo "ERROR: Failed to determine Spotify version."
            exit 1
        fi

        echo "Current version: $current_version"

        echo "Checking for updates..."
        local display_version full_version
        read -r display_version full_version <<<"$(getLatestVersion)"

        if [ -z "$display_version" ] || [ -z "$full_version" ]; then
            echo "ERROR: Failed to fetch latest Spotify version."
            exit 1
        fi

        echo "Latest version: $display_version"

        if [[ "$current_version" == "$display_version" ]]; then
            echo "You have the latest version of Spotify."
        else
            echo "A newer version of Spotify is available."
            if [ "$NONINTERACTIVE" = true ]; then
                echo "Running in non-interactive mode. Installing update automatically."
                downloadAndInstallSpotify "$display_version" "$full_version"
            else
                read -p "Do you want to update? (y/n): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    downloadAndInstallSpotify "$display_version" "$full_version"
                else
                    echo "Update canceled."
                fi
            fi
        fi
    else
        echo "Spotify is not installed."
        if [ "$NONINTERACTIVE" = true ]; then
            echo "Running in non-interactive mode. Installing Spotify automatically."
            local display_version full_version
            read -r display_version full_version <<<"$(getLatestVersion)"
            downloadAndInstallSpotify "$display_version" "$full_version"
        else
            read -p "Do you want to install Spotify? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                local display_version full_version
                read -r display_version full_version <<<"$(getLatestVersion)"
                downloadAndInstallSpotify "$display_version" "$full_version"
            else
                echo "Installation canceled."
            fi
        fi
    fi
}

# call main function
main
