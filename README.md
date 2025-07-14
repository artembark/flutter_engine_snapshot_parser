# Flutter Engine Snapshot Parser

A Dart tool that automatically parses Flutter engine snapshots from official releases and extracts snapshot hashes from engine binaries.

## Features

- 🔄 **Incremental Updates**: Only processes new Flutter releases, skipping already parsed versions
- 📊 **CSV Output**: Generates a comprehensive CSV file with release metadata and snapshot hashes
- 🚀 **Automated Daily Updates**: GitHub Action runs daily to keep data current

## Data Fields

The generated `output/enginehash.csv` contains:

- `channel` - Flutter release channel (stable, beta, dev)
- `flutter_version` - Flutter version number
- `dart_sdk_version` - Dart SDK version
- `release_date` - Official release date
- `flutter_release_commit_hash` - Flutter repository commit hash
- `engine_version_commit_hash` - Engine repository commit hash
- `snapshot_hash` - 32-character snapshot hash extracted from gen_snapshot binary

## Usage

### Manual Run

```bash
# Install dependencies
dart pub get

# Run the parser
dart run bin/flutter_engine_snapshot_parser.dart
```

### Automated Updates

This repository includes a GitHub Action that:

- Runs daily at 6:00 AM UTC
- Checks for new Flutter releases
- Updates the CSV file with new snapshot data
- Commits changes automatically

You can also trigger the workflow manually from the GitHub Actions tab.

## How It Works

1. **Reads Existing Data**: Checks the current CSV file to determine the newest processed release
2. **Clones Flutter Repo**: Downloads the Flutter repository to access engine version files
3. **Fetches Release List**: Downloads the official Flutter releases JSON from Google Cloud Storage
4. **Processes New Releases**: For each new release:
   - Extracts the engine version hash from `bin/internal/engine.version`
   - Downloads the corresponding engine artifacts
   - Extracts the snapshot hash from the `gen_snapshot` binary
5. **Updates CSV**: Adds new entries at the top of the file (newest first)

## Requirements

- Dart SDK
- Git (for cloning Flutter repository)
- Internet connection (for downloading releases and artifacts)

## Output

Results are saved to `output/enginehash.csv` with the newest releases at the top.
