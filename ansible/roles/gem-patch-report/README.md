# Gem Patch Report Role

This Ansible role generates reports on Ruby gems that had security vulnerabilities at the beginning of the current month and have since been patched. It compares the Gemfile.lock from the start of the month (retrieved from the Capistrano git repo) against the current Gemfile.lock using bundle-audit, and reports only the gems that have been fixed.

## Requirements

- Ruby application deployed with Capistrano (requires the `repo/` directory)
- bundler-audit gem (automatically installed if missing)
- Stats server configuration (same as other subspace roles)

## Role Variables

Available variables with their default values:

```yaml
# Path to the Rails/Ruby application (Capistrano current symlink)
gem_patch_report_app_path: "/u/apps/{{project_name}}/current"

# Required for stats reporting (inherited from other roles)
send_stats: false
stats_url: ""
stats_api_key: ""
hostname: ""
```

## Usage

1. Enable the role in your playbook:
   ```yaml
   roles:
     - gem-patch-report
   ```

2. Configure the required variables:
   ```yaml
   send_stats: true
   stats_url: "https://your-stats-server.com/api/stats"
   stats_api_key: "your-api-key"
   ```

## How It Works

1. Retrieves the Gemfile.lock from the last commit before the 1st of the current month using the Capistrano bare git repo at `<deploy_to>/repo/`
2. Runs `bundle-audit` against both the old and current Gemfile.lock
3. Compares the results to identify vulnerabilities that existed at the start of the month but are no longer present (i.e. patched)
4. Outputs a report containing only the patched gems

## Bundle-Audit Input Format

The role processes JSON output from `bundle-audit check --format json`. Here's the simplified structure:

```json
{
  "version": "0.9.2",
  "created_at": "2026-03-06 12:16:58 -0600",
  "results": [
    {
      "type": "unpatched_gem",
      "gem": {
        "name": "nokogiri",
        "version": "1.18.9"
      },
      "advisory": {
        "id": "GHSA-wx95-c6cv-8532",
        "title": "Nokogiri does not check the return value from xmlC14NExecute",
        "criticality": "medium",
        "cve": null,
        "patched_versions": [">= 1.19.1"]
      }
    }
  ]
}
```

### Key Fields Used

The role extracts data from these fields:
- `results[].type` - Filters for `"unpatched_gem"`
- `results[].gem.name` - Gem name
- `results[].gem.version` - Vulnerable version
- `results[].advisory.id` - Advisory ID (CVE, GHSA, etc.)
- `results[].advisory.criticality` - Severity level

## Report Format

The role generates a JSON array of gems that were patched during the current month. If a gem had multiple advisories that were all fixed, each advisory appears as its own entry.

```json
[
  {
    "name": "activestorage",
    "version": "8.0.2.1",
    "current_version": "8.0.4.1",
    "advisory_id": "CVE-2026-33658",
    "criticality": null
  },
  {
    "name": "bcrypt",
    "version": "3.1.20",
    "current_version": "3.1.22",
    "advisory_id": "CVE-2026-33306",
    "criticality": null
  },
  {
    "name": "devise",
    "version": "4.9.4",
    "current_version": "5.0.3",
    "advisory_id": "CVE-2026-32700",
    "criticality": null
  }
]
```

### Gem Objects

Each gem object contains:
- `name`: The gem name
- `version`: The vulnerable version from the start of the month
- `current_version`: The current patched version (parsed from the current Gemfile.lock)
- `advisory_id`: The security advisory ID (CVE, GHSA, etc.)
- `criticality`: The severity level (low, medium, high, critical, or null if not specified)

## Tags

This role supports the following tags:
- `maintenance`
- `stats`
- `gem-patch-report`

## Error Handling

The role includes error handling for common scenarios:
- Missing Gemfile.lock
- No git history before the current month
- bundle-audit execution failures

Errors are logged but don't fail the entire playbook execution. If no patched gems are found, an empty array `[]` is reported.
