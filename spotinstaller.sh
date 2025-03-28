#!/usr/bin/env bash

# Constants
readonly SPOTIFY_INSTALL_PATH="$HOME/.local/share/spotify"
readonly SPOTIFY_DEB_FILE="/tmp/spotify.deb"
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

    # Copy files to appropriate locations
    sudo cp -r "$temp_dir/usr" "$SPOTIFY_INSTALL_PATH"

    # symlink spotify to $HOME/.local/bin
    sudo ln -s "$SPOTIFY_INSTALL_PATH/bin/spotify" "$HOME/.local/bin/spotify"

    # symlink spotify.desktop to $HOME/.local/share/applications
    sudo ln -s "$SPOTIFY_INSTALL_PATH/share/spotify.desktop" "$HOME/.local/share/applications/spotify.desktop"

    # Clean up
    rm -rf "$temp_dir"
}

function downloadSpotify() {
    local display_version="$1"
    local full_version="$2"
    local download_url="$SPOTIFY_DOWNLOAD_URL/spotify-client_${full_version}_amd64.deb"
    local deb_file="$SPOTIFY_DEB_FILE"

    echo "Downloading Spotify version ${display_version}..."
    if ! curl -L -o "$deb_file" "$download_url"; then
        echo "Failed to download Spotify. Please check your internet connection."
        return 1
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
        echo "Your distribution is not supported yet."
        rm "$deb_file"
        return 1
        ;;
    esac

    rm "$deb_file"
    echo "Spotify has been installed/updated successfully in $HOME/.local/share/spotify"
}

function downloadAndInstallSpotify() {
    local display_version="$1"
    local full_version="$2"

    local deb_file
    if ! deb_file=$(downloadSpotify "$display_version" "$full_version"); then
        return 1
    fi

    installSpotify "$deb_file"
}

function main() {
    printLogo

    # distro check
    local distro_type
    distro_type=$(getDistroType)

    if [ "$distro_type" == "unsupported" ]; then
        echo "Your distribution is not supported yet."
        return 1
    fi

    if isSpotifyInstalled; then
        echo "Spotify is installed."
        local current_version
        current_version=$(getSpotifyVersion)
        echo "Current version: $current_version"

        echo "Checking for updates..."
        local display_version full_version
        read -r display_version full_version <<<"$(getLatestVersion)"
        echo "Latest version: $display_version"

        if [[ "$current_version" == "$display_version" ]]; then
            echo "You have the latest version of Spotify."
        else
            echo "A newer version of Spotify is available."
            read -p "Do you want to update? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                downloadAndInstallSpotify "$display_version" "$full_version"
            else
                echo "Update canceled."
            fi
        fi
    else
        echo "Spotify is not installed."
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
}

# call main function
main
