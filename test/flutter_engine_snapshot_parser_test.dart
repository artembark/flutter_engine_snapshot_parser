import 'dart:io';

import 'package:flutter_engine_snapshot_parser/snapshot_extractor.dart';
import 'package:test/test.dart';

void main() {
  group('Snapshot Hash Validation', () {
    test('should validate correct 32-character hex hash', () {
      expect(isValidSnapshotHash('478acceee22b35bdc3f900f25fbf034e'), isTrue);
      expect(isValidSnapshotHash('830f4f59e7969c70b595182826435c19'), isTrue);
      expect(isValidSnapshotHash('b3e43f5515d5dccf94e318501ab449d2'), isTrue);
    });

    test('should reject invalid hash lengths', () {
      expect(isValidSnapshotHash(''), isFalse);
      expect(isValidSnapshotHash('123'), isFalse);
      expect(isValidSnapshotHash('478acceee22b35bdc3f900f25fbf034e1'), isFalse); // 33 chars
      expect(isValidSnapshotHash('478acceee22b35bdc3f900f25fbf034'), isFalse); // 31 chars
    });

    test('should reject non-hexadecimal characters', () {
      expect(isValidSnapshotHash('478acceee22b35bdc3f900f25fbf034g'), isFalse); // 'g' not hex
      expect(isValidSnapshotHash('478acceee22b35bdc3f900f25fbf034Z'), isFalse); // 'Z' not hex
      expect(isValidSnapshotHash('478acceee22b35bdc3f900f25fbf03!e'), isFalse); // '!' not hex
    });

    test('should accept both uppercase and lowercase hex', () {
      expect(isValidSnapshotHash('478ACCEEE22B35BDC3F900F25FBF034E'), isTrue);
      expect(isValidSnapshotHash('478acceee22b35bdc3f900f25fbf034e'), isTrue);
      expect(isValidSnapshotHash('478AcCeEe22B35bDc3F900f25FbF034E'), isTrue);
    });
  });

  group('CSV Line Validation', () {
    test('should validate correct CSV format', () {
      const validLine =
          'stable,3.32.5,3.8.1,2025-06-25T18:28:34.724785Z,fcf2c11572af6f390246c056bc905eca609533a0,dd93de6fb1776398bf586cbd477deade1391c7e4,830f4f59e7969c70b595182826435c19';
      expect(isValidCsvLine(validLine), isTrue);
    });

    test('should reject CSV lines with wrong number of fields', () {
      expect(isValidCsvLine('stable,3.32.5,3.8.1'), isFalse); // Too few fields
      expect(isValidCsvLine('stable,3.32.5,3.8.1,date,hash1,hash2,hash3,extra'),
          isFalse); // Too many fields
      expect(isValidCsvLine(''), isFalse); // Empty line
    });

    test('should handle CSV lines with empty fields', () {
      const lineWithEmptyFields =
          'stable,,3.8.1,2025-06-25T18:28:34.724785Z,fcf2c11572af6f390246c056bc905eca609533a0,dd93de6fb1776398bf586cbd477deade1391c7e4,830f4f59e7969c70b595182826435c19';
      expect(isValidCsvLine(lineWithEmptyFields), isTrue); // Still 7 fields, even if some empty
    });
  });

  group('Snapshot Hash Extraction', () {
    test('should extract hash from test file with embedded hash', () async {
      // Create a temporary test file with a hash embedded
      final tempDir = await Directory.systemTemp.createTemp('test_');
      final testFile = File('${tempDir.path}/test_binary');

      // Create test content with embedded hash
      final testHash = '478acceee22b35bdc3f900f25fbf034e';
      final binaryContent = [
        0x00, 0x01, 0x02, // Non-printable bytes
        ...testHash.codeUnits, // The hash as ASCII
        0x00, 0x01, 0x02, // More non-printable bytes
      ];

      await testFile.writeAsBytes(binaryContent);

      final extractedHash = getSnapshotHashFromPath(testFile.path);
      expect(extractedHash, equals(testHash));

      // Cleanup
      await tempDir.delete(recursive: true);
    });

    test('should return empty string for file without hash', () async {
      final tempDir = await Directory.systemTemp.createTemp('test_');
      final testFile = File('${tempDir.path}/test_binary');

      // Create test content without valid hash
      final binaryContent = [
        0x00, 0x01, 0x02, // Non-printable bytes
        ...'This is just some text without a valid 32char hash'.codeUnits,
        0x00, 0x01, 0x02, // More non-printable bytes
      ];

      await testFile.writeAsBytes(binaryContent);

      final extractedHash = getSnapshotHashFromPath(testFile.path);
      expect(extractedHash, equals(''));

      // Cleanup
      await tempDir.delete(recursive: true);
    });

    test('should return empty string for non-existent file', () {
      final extractedHash = getSnapshotHashFromPath('/non/existent/file');
      expect(extractedHash, equals(''));
    });

    test('should find first valid hash when multiple patterns exist', () async {
      final tempDir = await Directory.systemTemp.createTemp('test_');
      final testFile = File('${tempDir.path}/test_binary');

      // Create test content with multiple potential hashes
      final firstHash = '478acceee22b35bdc3f900f25fbf034e';
      final secondHash = 'b3e43f5515d5dccf94e318501ab449d2';
      final binaryContent = [
        0x00,
        0x01,
        0x02,
        ...firstHash.codeUnits,
        0x00,
        0x01,
        0x02,
        ...secondHash.codeUnits,
        0x00,
        0x01,
        0x02,
      ];

      await testFile.writeAsBytes(binaryContent);

      final extractedHash = getSnapshotHashFromPath(testFile.path);
      expect(extractedHash, equals(firstHash)); // Should return the first one found

      // Cleanup
      await tempDir.delete(recursive: true);
    });
  });
}
