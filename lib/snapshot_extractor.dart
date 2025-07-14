import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;

/// Downloads engine artifacts and extracts the snapshot hash from gen_snapshot binary
///
/// This function:
/// 1. Downloads the engine ZIP file from Google Cloud Storage
/// 2. Extracts the archive to a temporary directory
/// 3. Locates the gen_snapshot binary within the extracted files
/// 4. Extracts the 32-character snapshot hash from the binary
/// 5. Cleans up temporary files
///
/// The snapshot hash is embedded in the gen_snapshot binary and is the same hash
/// that appears in compiled Flutter apps (in libapp.so)
/// Returns the 32-character snapshot hash, or null if extraction failed.
///
/// - [engineVersionHash] - engineVersionHash The engine commit hash to download artifacts for
Future<String?> getEngineSnapshotHash(String engineVersionHash) async {
  try {
    /// Define paths for temporary files during processing
    final zipFilePath = 'output/$engineVersionHash.zip';
    final engineHashPath = 'output/$engineVersionHash';

    /// Construct URL for the engine artifacts
    /// We use android-arm64-release/linux-x64.zip which contains the gen_snapshot binary
    final url =
        'https://storage.googleapis.com/flutter_infra_release/flutter/$engineVersionHash/android-arm64-release/linux-x64.zip';
    print('Fetching zip from $url');

    /// Download the engine ZIP file
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      /// Save the downloaded ZIP file to disk
      final file = File(zipFilePath);
      await file.create(recursive: true);
      await file.writeAsBytes(response.bodyBytes);

      /// Extract the ZIP archive to a temporary directory
      final bytes = file.readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);
      await extractArchiveToDisk(archive, engineHashPath);

      /// Look for the gen_snapshot binary in the extracted files
      final genSnapshotFilePath = path.join(engineHashPath, 'gen_snapshot');
      if (File(genSnapshotFilePath).existsSync()) {
        /// Extract the snapshot hash from the gen_snapshot binary
        /// This hash is embedded in the binary and matches what appears in compiled Flutter apps
        final engineSnapshotHash = getSnapshotHashFromPath(genSnapshotFilePath);

        /// Clean up temporary files to save disk space
        await file.delete();
        Directory(engineHashPath).deleteSync(recursive: true);

        return engineSnapshotHash.toString();
      }
    }
    return null;
  } catch (e, s) {
    print('Error getting snapshot hash: $e, $s');
    return null;
  }
}

/// Extracts a 32-character hexadecimal snapshot hash from a binary file
///
/// This function reads a binary file (gen_snapshot) and searches for a 32-character
/// hexadecimal string that represents the Dart VM snapshot hash. The hash is embedded
/// in the binary as printable ASCII characters.
///
/// Algorithm:
/// 1. Read file as raw bytes
/// 2. Convert printable bytes (ASCII 32-126) to characters
/// 3. Build strings of printable characters
/// 4. Search for 32-character hex patterns using regex
/// 5. Return the first valid hash found
///
/// @param filePath Path to the binary file to scan
/// @return The 32-character snapshot hash, or empty string if not found
String getSnapshotHashFromPath(String filePath) {
  File file = File(filePath);
  final stringBuffer = StringBuffer();

  try {
    /// Read the entire binary file as raw bytes
    List<int> fileBytes = file.readAsBytesSync();

    /// Process each byte in the file
    for (var byte in fileBytes) {
      /// Check if byte represents a printable ASCII character (space to tilde)
      if (byte >= 32 && byte <= 126) {
        /// Convert printable byte to character and add to buffer
        stringBuffer.write(String.fromCharCode(byte));
        continue;
      }

      /// When we hit a non-printable byte, check if we have enough characters
      /// to potentially contain a 32-character hash
      if (stringBuffer.length >= 32) {
        /// Search for 32-character hexadecimal pattern (a-f, A-F, 0-9)
        RegExp re = RegExp(r'([a-fA-F\d]{32})');
        Iterable<RegExpMatch> matches = re.allMatches(stringBuffer.toString());
        if (matches.isNotEmpty) {
          /// Found a valid 32-character hash, return it
          return matches.first.group(0)!;
        }
      }

      /// Clear buffer when we hit non-printable characters to start fresh
      stringBuffer.clear();
    }

    /// No hash found in the file
    return '';
  } catch (e) {
    /// Return empty string on error instead of exiting
    /// Original bin version would print and exit, but lib should be more graceful
    return '';
  }
}

/// Validates if a string is a valid 32-character hexadecimal hash
///
/// @param hash The string to validate
/// @return True if the string is a valid 32-character hex hash
bool isValidSnapshotHash(String hash) {
  if (hash.length != 32) return false;
  RegExp hexPattern = RegExp(r'^[a-fA-F0-9]{32}$');
  return hexPattern.hasMatch(hash);
}

/// Validates CSV line format for engine snapshot data
///
/// @param csvLine The CSV line to validate
/// @return True if the line has the expected number of fields
bool isValidCsvLine(String csvLine) {
  List<String> parts = csvLine.split(',');
  return parts.length ==
      7; // Expected: channel,version,dart_version,date,flutter_hash,engine_hash,snapshot_hash
}
