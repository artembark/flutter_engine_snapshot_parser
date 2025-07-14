import 'dart:convert';
import 'dart:io';

import 'package:flutter_engine_snapshot_parser/snapshot_extractor.dart';
import 'package:http/http.dart' as http;

/// Path to the CSV file where results will be stored
const String logFilePath = 'output/enginehash.csv';

/// Temporary directory for cloning Flutter repository
const String tempFlutterRepositoryPath = './flutter';

/// Main function that parses Flutter engine snapshots
/// This function:
/// 1. Reads existing CSV data to avoid duplicates
/// 2. Clones Flutter repository for git operations
/// 3. Downloads Flutter releases list from Google Storage
/// 4. Processes only new releases (stops when reaching existing ones)
/// 5. Downloads engine artifacts and extracts snapshot hashes
/// 6. Updates CSV file with new entries at the top
Future<void> main() async {
  final logFile = File(logFilePath);

  /// Variables to track existing data and control parsing
  String? firstExistingReleaseHash;
  List<String> existingLines = [];

  /// CSV header defining the structure of our output file
  const String headerLine =
      'channel,flutter_version,dart_sdk_version,release_date,flutter_release_commit_hash,engine_version_commit_hash,snapshot_hash';

  /// Check if CSV file already exists and read existing data
  /// We only need the first data entry (second line) to know when to stop parsing
  /// This optimization allows us to process only new releases
  if (logFile.existsSync()) {
    final lines = logFile.readAsLinesSync();
    if (lines.length > 1) {
      existingLines = lines.skip(1).toList(); // Skip header line
      final firstDataLine = lines[1]; // Get the newest existing entry
      final parts = firstDataLine.split(',');
      if (parts.length >= 5) {
        /// Extract the Flutter release commit hash (5th column) as our stop condition
        firstExistingReleaseHash = parts[4]; // flutter_release_commit_hash
      }
    }
  } else {
    /// Create the output directory and file if they don't exist
    logFile.createSync(recursive: true);
  }

  /// Clean up any existing Flutter repository clone to ensure fresh start
  final flutterDirectory = Directory(tempFlutterRepositoryPath);
  if (flutterDirectory.existsSync()) {
    flutterDirectory.deleteSync(recursive: true);
  }

  /// Clone the Flutter repository to access git history and engine.version files
  /// This is needed to get engine version hashes for each Flutter release
  await Process.run(
      'git', ['clone', 'https://github.com/flutter/flutter.git', tempFlutterRepositoryPath]);

  /// Download the official Flutter releases list from Google Cloud Storage
  /// This JSON contains all Flutter releases with metadata we need
  final response = await http.get(Uri.parse(
      'https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json'));
  final releases = json.decode(response.body)['releases'];

  /// List to collect new entries before writing to file
  List<String> newEntries = [];

  /// Process each Flutter release from the official releases list
  /// The releases are ordered by date (newest first), so we can stop early
  for (var data in releases) {
    print('-----------------------');

    /// Extract the Flutter release commit hash - this uniquely identifies each release
    final flutterReleaseCommitHash = data['hash'] as String;

    /// OPTIMIZATION: Stop parsing if we reach a release we already have
    /// Since releases are ordered newest-first, this prevents re-processing old data
    if (firstExistingReleaseHash != null && flutterReleaseCommitHash == firstExistingReleaseHash) {
      print('Reached existing release: ${data['version']} ($flutterReleaseCommitHash) - stopping');
      break;
    }

    print('Processing new release: ${data['version']} ($flutterReleaseCommitHash)');

    /// Get the engine version hash from the Flutter repository at this specific commit
    /// The bin/internal/engine.version file contains the engine commit hash used by this Flutter version
    final searchVersionResult = await Process.run(
      'git',
      ['cat-file', '-p', '$flutterReleaseCommitHash:bin/internal/engine.version'],
      workingDirectory: flutterDirectory.path,
    );

    String engineVersionCommitHash = '';
    if (searchVersionResult.exitCode == 0) {
      /// Successfully found the engine version file
      engineVersionCommitHash = searchVersionResult.stdout.toString().trim();
      print('Engine version hash: $engineVersionCommitHash');
    } else {
      /// Some early releases (like 3.9.0-0.1.pre) don't have engine.version file
      /// This is expected for certain pre-release versions
      print('Error: ${searchVersionResult.stderr}');
      continue;
    }

    /// Download engine artifacts and extract the snapshot hash
    /// This is the core functionality - getting the actual snapshot hash from engine binaries
    final engineSnapshotHash = await getEngineSnapshotHash(engineVersionCommitHash);

    if (engineSnapshotHash != null) {
      /// Create a CSV entry with all the collected information
      /// Format: channel,version,dart_version,date,flutter_hash,engine_hash,snapshot_hash
      final newEntry =
          '${data['channel']},${data['version']},${data['dart_sdk_version']},${data['release_date']},'
          '$flutterReleaseCommitHash,$engineVersionCommitHash,$engineSnapshotHash';
      newEntries.add(newEntry);
      print('New entry added: $newEntry');
    }
  }

  /// Write the complete CSV file with new entries at the top
  /// This ensures the newest releases appear first in the output file
  final allLines = <String>[];
  allLines.add(headerLine); // Always include header as first line
  allLines.addAll(newEntries); // Add new entries first (newest releases)
  allLines.addAll(existingLines); // Then add existing entries (older releases)

  /// Write all content to file in one operation
  logFile.writeAsStringSync('${allLines.join('\n')}\n');

  /// Provide feedback on what was accomplished
  if (newEntries.isNotEmpty) {
    print('Added ${newEntries.length} new entries to $logFilePath');
  } else {
    print('No new entries found. File updated with existing entries.');
  }

  print('Parsing finished, output is in $logFilePath');

  /// Clean up the temporary Flutter repository
  flutterDirectory.deleteSync(recursive: true);
}
