# ZMedia Player - Automated Release Workflow Plan

## Overview

This document outlines the automated release strategy for ZMedia Player using semantic versioning, automated changelog generation, and GitHub releases.

## Semantic Versioning Strategy

### Version Format: `MAJOR.MINOR.PATCH`

- **MAJOR** (1.x.x): Breaking changes, incompatible API changes
- **MINOR** (x.1.x): New features, backward-compatible functionality
- **PATCH** (x.x.1): Bug fixes, backward-compatible patches

### Conventional Commits

The release workflow uses conventional commits to automatically determine version bumps:

```
feat: New feature (MINOR version bump)
fix: Bug fix (PATCH version bump)
perf: Performance improvement (PATCH version bump)
docs: Documentation only (no version bump)
style: Code style changes (no version bump)
refactor: Code refactoring (PATCH version bump)
test: Test changes (no version bump)
chore: Maintenance tasks (no version bump)

BREAKING CHANGE: (MAJOR version bump)
  - Include in commit body or footer
  - Example: "BREAKING CHANGE: Remove deprecated API"
```

### Version Bump Rules

1. **MAJOR bump** if:
   - Any commit contains `BREAKING CHANGE:` in body/footer
   - Manual override via workflow input

2. **MINOR bump** if:
   - Commits contain `feat:` prefix
   - No breaking changes

3. **PATCH bump** if:
   - Commits contain `fix:`, `perf:`, or `refactor:`
   - No features or breaking changes

## Release Workflow Triggers

### 1. Manual Release (Recommended)
- **Trigger**: GitHub Actions manual dispatch
- **When**: After significant changes are merged to main
- **Options**:
  - Version bump type (auto/major/minor/patch)
  - Pre-release flag (alpha/beta/rc)
  - Dry run mode (test without releasing)

### 2. Automatic Release (Optional)
- **Trigger**: Push to main branch with specific commit message
- **Pattern**: Commit message starts with `release:`
- **Example**: `release: v1.2.0`

### 3. Tag-based Release
- **Trigger**: Push tag matching `v*.*.*` pattern
- **When**: Manual tag creation
- **Use case**: Emergency releases

## Release Process Steps

### Step 1: Version Detection & Bump
1. Analyze commits since last release
2. Determine version bump using conventional commits
3. Update `pubspec.yaml` with new version
4. Update version in platform-specific files (if needed)

### Step 2: Changelog Generation
1. Generate changelog from conventional commits
2. Group changes by type:
   - 🚀 Features
   - 🐛 Bug Fixes
   - ⚡ Performance Improvements
   - 📚 Documentation
   - 🔧 Refactoring
   - 💥 Breaking Changes
3. Include commit author and PR links
4. Prepend to `CHANGELOG.md`

### Step 3: Git Operations
1. Create release branch: `release/v{version}`
2. Commit version bump and changelog
3. Create signed git tag: `v{version}`
4. Push branch and tag to origin

### Step 4: GitHub Release
1. Create GitHub release from tag
2. Generate release notes:
   - Auto-generated from changelog
   - Include highlights section (customizable)
   - List of contributors
   - Installation instructions
3. Attach release assets:
   - Source code (auto)
   - Optional: Compiled binaries

### Step 5: Post-Release (GitHub Only)
1. Create PR to merge release branch to main
2. Update documentation site (if applicable)
3. Notify stakeholders via Slack/Discord (optional)
4. Close milestone (if using GitHub milestones)

## Changelog Configuration

### Format
```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.2.0] - 2025-01-15

### Features
- Add Picture-in-Picture support for iOS (#123) @contributor
- Implement adaptive streaming for live content (#124) @contributor

### Bug Fixes
- Fix memory leak in MediaController disposal (#125) @contributor
- Resolve DRM session timeout issues (#126) @contributor

### Breaking Changes
- Remove deprecated `MediaConfig.autoLoop` parameter (#127) @contributor
  - Migration: Use `repeatMode: RepeatMode.all` instead
```

### Customization Points
1. **Section Headers**: Configurable via `.changelogrc`
2. **Commit Filtering**: Exclude certain commit types
3. **Author Attribution**: Include/exclude contributors
4. **PR Links**: Auto-link to GitHub PRs
5. **Custom Sections**: Add project-specific sections

## Release Notes Template

### Default Template
```markdown
## ZMedia Player v{version}

### Highlights
{manually_curated_highlights}

### What's Changed
{auto_generated_changelog}

### Contributors
{contributor_list}

### Installation

Add to your `pubspec.yaml`:
```yaml
dependencies:
  zmedia_player: ^{version}
```

Then run:
```bash
flutter pub get
```

### Documentation
- [API Reference](https://docs.example.com/api)
- [Migration Guide](https://docs.example.com/migration)
- [Examples](https://github.com/zionmedianetwork/zmedia_player/tree/main/example)

**Full Changelog**: https://github.com/zionmedianetwork/zmedia_player/compare/v{previous_version}...v{version}
```

### Customization Options
1. **Highlights Section**: Manually edit before release
2. **Breaking Changes Notice**: Auto-highlighted in red
3. **Migration Guide**: Link to migration docs for MAJOR releases
4. **Assets Section**: List downloadable assets
5. **Footer**: Customizable footer with links

## Git Tagging Strategy

### Tag Format
- **Stable Releases**: `v{major}.{minor}.{patch}` (e.g., `v1.2.3`)
- **Pre-releases**: `v{major}.{minor}.{patch}-{label}.{number}` (e.g., `v1.3.0-beta.1`)

### Tag Annotations
```
v1.2.3

Release v1.2.3 - ZMedia Player

Features:
- Picture-in-Picture support
- Adaptive streaming for live content

Bug Fixes:
- Memory leak fixes
- DRM session improvements

See full release notes: https://github.com/zionmedianetwork/zmedia_player/releases/tag/v1.2.3
```

### Tag Signing
- All release tags should be GPG signed
- Ensures authenticity and integrity
- Required for pub.dev publishing

## Version Preservation

### Git Tags
- ✅ **All versions preserved as Git tags**
- ✅ Never delete release tags
- ✅ Tags are immutable (cannot be changed)

### GitHub Releases
- ✅ **All releases preserved in GitHub**
- ✅ Release assets stored permanently
- ✅ Release notes editable after creation

### Package Distribution
- ✅ **All versions available via GitHub releases**
- ✅ Users can install any version using Git references
- ✅ pub.dev publishing planned for future releases

### Changelog
- ✅ **Complete history in CHANGELOG.md**
- ✅ Committed to main branch
- ✅ Versioned with code

## Pre-release Workflow

### Alpha Releases (Early Development)
- **Version**: `v1.3.0-alpha.1`
- **Trigger**: Manual workflow dispatch with `--pre-release alpha`
- **Use case**: Internal testing, breaking changes
- **Publish**: GitHub only

### Beta Releases (Feature Complete)
- **Version**: `v1.3.0-beta.1`
- **Trigger**: Manual workflow dispatch with `--pre-release beta`
- **Use case**: Public testing, feature freeze
- **Publish**: GitHub only

### Release Candidates (Stabilization)
- **Version**: `v1.3.0-rc.1`
- **Trigger**: Manual workflow dispatch with `--pre-release rc`
- **Use case**: Final testing before stable release
- **Publish**: GitHub only

## Workflow Security

### Required Secrets
1. **GITHUB_TOKEN**: Auto-provided by GitHub Actions (required)
2. **GPG_PRIVATE_KEY**: For signing tags (optional, recommended for production)

### Permissions
- **contents: write**: Create tags and releases
- **pull-requests: write**: Create release PRs

### Branch Protection
- Require status checks before release
- Require code review for release branches
- Prevent force-push to release tags

## Rollback Strategy

### In Case of Bad Release

#### Option 1: Patch Release (Recommended)
1. Fix the issue in a new commit
2. Create patch release (e.g., `v1.2.4`)
3. Publish new version
4. Mark bad version as deprecated

#### Option 2: Tag Deletion (Emergency Only)
1. Delete remote tag: `git push origin :refs/tags/v1.2.3`
2. Delete local tag: `git tag -d v1.2.3`
3. Delete GitHub release
4. ⚠️ **Not recommended** - breaks version history

## Monitoring & Notifications

### Success Notifications
- ✅ GitHub release created
- ✅ Slack/Discord webhook (optional)
- ✅ Email to maintainers (optional)

### Failure Notifications
- ❌ GitHub Actions failure notification
- ❌ Slack/Discord alert with error details
- ❌ Create GitHub issue for failed release

## Workflow Files

### Primary Workflow
1. **`.github/workflows/release.yml`**
   - Main release workflow
   - Handles version bumping, changelog, tagging
   - Creates GitHub releases
   - Supports stable and pre-release versions

### Configuration Files
1. **`.changelogrc`** or **`changelog.config.js`**
   - Changelog generation settings
   - Commit types, sections, formatting

2. **`.github/release.yml`**
   - GitHub auto-generated release notes config
   - Categories, labels, exclude patterns

3. **`.github/release-template.md`**
   - Custom release notes template
   - Placeholders for dynamic content

## Best Practices

### Commit Messages
✅ **DO**:
- `feat: Add Chromecast support for Android devices`
- `fix: Resolve memory leak in MediaController disposal`
- `perf: Optimize HLS segment loading performance`

❌ **DON'T**:
- `Update code`
- `Fix bug`
- `WIP`

### Release Timing
- **Weekly**: Patch releases for bug fixes
- **Bi-weekly/Monthly**: Minor releases for features
- **Quarterly/As-needed**: Major releases for breaking changes

### Version Planning
- Use GitHub milestones for version planning
- Group issues/PRs by target version
- Close milestone when releasing

### Testing Before Release
1. Run full test suite
2. Test on real devices (Android + iOS)
3. Check example app functionality
4. Validate breaking changes are documented

## Example Release Commands

### Manual Release via GitHub Actions UI
1. Go to Actions → Release Workflow
2. Click "Run workflow"
3. Select options:
   - Branch: `main`
   - Version bump: `auto`
   - Pre-release: `none`
   - Dry run: `false`
4. Click "Run workflow"

### Manual Release via gh CLI
```bash
# Trigger release workflow
gh workflow run release.yml \
  --ref main \
  -f version_bump=auto \
  -f pre_release=none \
  -f dry_run=false

# Create pre-release
gh workflow run release.yml \
  --ref main \
  -f version_bump=minor \
  -f pre_release=beta \
  -f dry_run=false
```

### Manual Tag Release
```bash
# Create and push tag
git tag -a v1.2.3 -m "Release v1.2.3"
git push origin v1.2.3

# Workflow will automatically create release
```

## Future Enhancements

### Phase 2
- [ ] Automated API documentation generation
- [ ] Performance benchmarking in releases
- [ ] Automated security scanning
- [ ] Release metrics dashboard

### Phase 3
- [ ] Multi-platform binary builds (if applicable)
- [ ] Automated migration guides
- [ ] Release announcement blog posts
- [ ] Integration with project management tools

## Support & Maintenance

### Workflow Maintenance
- Review and update workflows quarterly
- Update dependencies (actions versions)
- Test workflows on feature branches
- Document workflow changes in this plan

### Troubleshooting
- Check GitHub Actions logs for errors
- Verify secrets are configured correctly
- Test locally with `act` (nektos/act) when possible
- Contact maintainers via GitHub discussions

---

**Document Version**: 1.0
**Last Updated**: 2025-01-15
**Owner**: ZMedia Player Maintainers
