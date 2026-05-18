# Releasing Guide

This guide covers how to create a new release of uttr.

## Version Numbering

We use [Semantic Versioning](https://semver.org/): **MAJOR.MINOR.PATCH**

## Release Checklist

### 1. Prepare the Release

- [ ] Update version in Xcode project (General → Version)
- [ ] Update `CHANGELOG.md` with changes since last release
- [ ] Commit: `git commit -m "chore: prepare v1.x.x release"`

### 2. Build the App

```bash
./build.sh -c Release
```

Or in Xcode: **Product → Archive**, then **Distribute App → Copy App**.

### 3. Create ZIP and Hash

```bash
cd /path/to/exported
zip -r uttr.zip uttr.app
shasum -a 256 uttr.zip
```

Save the SHA256 hash — you'll need it for the Homebrew cask.

### 4. Create Git Tag

```bash
git tag -a v1.x.x -m "Release v1.x.x"
git push origin v1.x.x
```

### 5. Create GitHub Release

1. Go to [GitHub Releases](https://github.com/ShishirAravindan/homebrew-uttr/releases)
2. Draft a new release against the tag
3. Attach `uttr.zip`
4. Publish

### 6. Update Homebrew Cask

In the tap repository (`Casks/uttr.rb`):

```ruby
version "1.x.x"
sha256 "YOUR_SHA256_HASH_HERE"
```

```bash
git commit -am "Update to v1.x.x"
git push
```

Users can then upgrade via:

```bash
brew upgrade --cask uttr
```

## Troubleshooting Releases

### Archive fails to build

- Check all Swift files compile without errors
- Ensure signing is set to "Sign to Run Locally"

### Users report "damaged" app

```bash
xattr -cr /Applications/uttr.app
```

### Homebrew formula doesn't update

```bash
brew update && brew upgrade --cask uttr
```
