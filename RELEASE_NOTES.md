# infravibe 2.11.0

Build-service setup now starts with a token and resource selection instead of manual API fields.

- GitHub Actions: connect with a personal access token, choose a repository and workflow, and add the monitor.
- GitLab: connect to gitlab.com or your own HTTPS server and select a project to monitor its latest pipeline.
- Azure DevOps: enter your organization URL and token, then choose a project and pipeline.
- GitHub and GitLab repository/project lists support loading additional pages. Manual setup remains available for other providers and resources outside discovery limits.
- Tokens stay in macOS Keychain. Monitoring access is checked before saving; browser sign-in is deferred.
- Release downloads and checksums now use `infravibe-2.11.0.dmg`. The contained app filename, bundle identifier, settings and updater signing identity remain compatible with existing installations.

Validation includes the Swift suite and fixtures for token discovery, resource selection, GitLab pipeline states and credential-free templates. Private-provider accounts have not been tested live.

Signed and notarized Universal macOS application for Apple silicon and Intel. Previous release 2.10.0 remains available for rollback.
