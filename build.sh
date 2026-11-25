#!/bin/sh
# Builds dist/AlbumFlow-<version>.zip from AlbumFlow/ and writes version, url and sha1 into repo.xml.
set -e
cd "$(dirname "$0")"
VER=$(sed -n 's#.*<version>\(.*\)</version>.*#\1#p' AlbumFlow/install.xml)
ZIP="AlbumFlow-$VER.zip"
mkdir -p dist && rm -f "dist/$ZIP"
(cd AlbumFlow && zip -qrX "../dist/$ZIP" . -x '.*' -x '*/.*')
SHA=$(shasum -a 1 "dist/$ZIP" | cut -d' ' -f1)
URL="https://github.com/trufy/AlbumFlow/releases/download/v$VER/$ZIP"
sed -i '' -e "/<plugin /s#version=\"[^\"]*\"#version=\"$VER\"#" -e "s#<url>.*</url>#<url>$URL</url>#" -e "s#<sha>.*</sha>#<sha>$SHA</sha>#" repo.xml
echo "dist/$ZIP  sha1 $SHA"
