# Testing Guide - ZMedia Player

## Overview

This guide covers testing strategies, test execution, and quality assurance for the ZMedia Player package.

> **Current status:** **578 tests passing** in the Dart layer (run `flutter test` for
> the live count). Native Kotlin/Swift code still has **no automated tests** — those
> paths require on-device verification.

## Test Structure

```
test/
├── models/              # Unit tests for data models
│   ├── drm_config_test.dart
│   └── media_item_test.dart
├── performance/         # Performance & benchmark tests
│   └── drm_performance_test.dart
├── test_utils/          # Test utilities and mocks
│   └── mocks.dart
└── widgets/             # Widget tests (to be added)
```

## Running Tests

### Run All Tests

```bash
# From project root
flutter test

# With coverage
flutter test --coverage

# View coverage report
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

### Run Specific Test Groups

```bash
# Unit tests only
flutter test test/models/

# Performance tests only
flutter test test/performance/

# Specific test file
flutter test test/models/drm_config_test.dart
```

### Run Tests with Verbose Output

```bash
flutter test --reporter expanded
```

## Test Categories

### 1. Unit Tests

Test individual components in isolation.

**Coverage Areas:**
- DRM configuration models
- Media item models
- License validation logic
- Serialization/deserialization
- State management

**Example:**
```dart
test('creates Widevine config correctly', () {
  final config = DrmConfig.widevine(
    licenseUrl: 'https://example.com/license',
  );

  expect(config.scheme, DrmScheme.widevine);
  expect(config.licenseUrl, 'https://example.com/license');
});
```

### 2. Widget Tests

Test UI components and user interactions.

**Coverage Areas:**
- DRM demo page
- Player controls
- Error displays
- License status indicators

**Example Structure:**
```dart
testWidgets('DRM demo page shows license status', (tester) async {
  await tester.pumpWidget(MyApp());
  await tester.tap(find.text('DRM Content Protection'));
  await tester.pumpAndSettle();

  expect(find.text('DRM Status:'), findsOneWidget);
});
```

### 3. Integration Tests

Test complete workflows end-to-end.

**Coverage Areas:**
- License acquisition flow
- Media playback with DRM
- Cast device discovery
- PiP mode transitions

**Setup:**
```bash
cd example
flutter test integration_test/
```

### 4. Performance Tests

Measure and benchmark performance metrics.

**Key Metrics:**
- DRM config creation time
- Serialization overhead
- License validation speed
- Memory footprint

**Thresholds:**
- Config creation: < 100μs
- Serialization: < 50μs
- License check: < 10μs
- Memory per config: ~1KB

## Test Utilities

### Mock Objects

Use pre-built mocks for consistent testing:

```dart
import '../test_utils/mocks.dart';

// Mock DRM configs
final widevineConfig = MockDrmConfigs.widevine;
final fairplayConfig = MockDrmConfigs.fairplay;

// Mock media items
final protectedVideo = MockMediaItems.widevineProtected;

// Mock licenses
final activeLicense = MockDrmLicenses.active;
final expiredLicense = MockDrmLicenses.expired;

// Mock sessions
final licensedSession = MockDrmSessions.licensed;
```

### Test Helpers

```dart
// Create custom test data
final config = TestHelpers.createDrmConfig(
  scheme: DrmScheme.widevine,
  licenseUrl: 'https://test.com/license',
);

// Validate DRM configuration
final isValid = TestHelpers.isValidDrmConfig(config);

// Time-based helpers
final futureExpiration = TestHelpers.expirationInFuture(
  Duration(days: 30),
);
```

## Platform-Specific Testing

### Android Testing

```bash
# Run on Android emulator
flutter test --platform android

# Test Widevine integration
flutter drive --target=test_driver/widevine_test.dart
```

**Check:**
- Widevine L1/L3 support
- License acquisition
- Offline playback
- Error handling

### iOS Testing

```bash
# Run on iOS simulator
flutter test --platform ios

# Test FairPlay integration
flutter drive --target=test_driver/fairplay_test.dart
```

**Check:**
- FairPlay certificate loading
- SPC/CKC exchange
- Content key session
- AirPlay with DRM

## Test Coverage Goals

### Minimum Coverage Targets

| Component | Target | Current |
|-----------|--------|---------|
| Models | 90% | Yes 95% |
| Core Logic | 85% | TBD |
| Widgets | 75% | TBD |
| Services | 80% | TBD |
| Overall | 80% | TBD |

### Generate Coverage Report

```bash
# Generate coverage
flutter test --coverage

# Generate HTML report
genhtml coverage/lcov.info -o coverage/html

# Open in browser
open coverage/html/index.html
```

## Common Test Patterns

### 1. Testing DRM Configuration

```dart
group('DrmConfig Validation', () {
  test('validates required fields', () {
    expect(
      () => DrmConfig(
        scheme: DrmScheme.widevine,
        licenseUrl: '',  // Invalid
      ),
      throwsArgumentError,
    );
  });

  test('accepts valid configuration', () {
    final config = DrmConfig.widevine(
      licenseUrl: 'https://valid-url.com/license',
    );

    expect(TestHelpers.isValidDrmConfig(config), true);
  });
});
```

### 2. Testing License Lifecycle

```dart
group('License Lifecycle', () {
  test('detects expired license', () {
    final license = DrmLicense(
      id: 'test',
      keyData: 'data',
      expirationTime: DateTime.now().subtract(Duration(hours: 1)),
    );

    expect(license.isExpired, true);
  });

  test('warns when license expiring soon', () {
    final license = DrmLicense(
      id: 'test',
      keyData: 'data',
      expirationTime: DateTime.now().add(Duration(minutes: 30)),
    );

    expect(license.isExpiringSoon, true);
  });
});
```

### 3. Testing Serialization

```dart
group('Serialization Round-Trip', () {
  test('preserves all data', () {
    final original = MediaItem(
      id: '1',
      title: 'Test',
      url: 'https://example.com/video.mp4',
      drmConfig: MockDrmConfigs.widevine,
    );

    final map = original.toMap();
    final deserialized = MediaItem.fromMap(map);

    expect(deserialized.id, original.id);
    expect(deserialized.drmConfig?.scheme, original.drmConfig?.scheme);
  });
});
```

## Continuous Integration

### GitHub Actions Example

```yaml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.16.0'

      - name: Install dependencies
        run: flutter pub get

      - name: Run tests
        run: flutter test --coverage

      - name: Upload coverage
        uses: codecov/codecov-action@v3
        with:
          files: ./coverage/lcov.info
```

## Best Practices

### 1. Test Naming

Use descriptive test names:

```dart
// Good
test('creates Widevine config with custom headers', () { ... });

// Bad
test('test1', () { ... });
```

### 2. Test Independence

Each test should be independent:

```dart
// Good
setUp(() {
  // Fresh state for each test
  testConfig = DrmConfig.widevine(
    licenseUrl: 'https://test.com/license',
  );
});

// Bad
final sharedConfig = DrmConfig.widevine(...);  // Shared mutable state
```

### 3. Use Matchers

Leverage Flutter's matchers:

```dart
// Good
expect(config.scheme, DrmScheme.widevine);
expect(license.isExpired, isFalse);
expect(items, hasLength(3));

// Bad
expect(config.scheme == DrmScheme.widevine, true);
```

### 4. Test Edge Cases

```dart
group('Edge Cases', () {
  test('handles null certificate URL for FairPlay', () { ... });
  test('handles empty license response', () { ... });
  test('handles network timeout', () { ... });
});
```

## Debugging Tests

### Print Debug Output

```dart
test('debug test', () {
  final config = MockDrmConfigs.widevine;
  print('Config: ${config.toMap()}');
  debugPrint('Debugging: $config');
});
```

### Run Single Test

```bash
flutter test test/models/drm_config_test.dart --name "creates Widevine"
```

### Use Test Debugger

```bash
# Run with debugger
flutter test --start-paused
```

## Performance Benchmarking

### Run Performance Tests

```bash
flutter test test/performance/

# With detailed output
flutter test test/performance/ --reporter expanded
```

### Interpret Results

```
DrmConfig creation: 45.23μs avg
Serialization: 32.15μs avg
License check: 5.67μs avg
```

### Performance Regression Detection

Tests will fail if performance degrades by more than 20%.

## Test Maintenance

### Regular Tasks

1. **Weekly:** Run full test suite
2. **Monthly:** Review and update test coverage
3. **Per Release:** Run performance benchmarks
4. **After Major Changes:** Update integration tests

### Updating Tests

When adding new features:

1. Write tests first (TDD)
2. Add mocks to `test_utils/mocks.dart`
3. Update this guide with new patterns
4. Verify coverage remains above targets

## Troubleshooting

### Common Issues

**Issue: Tests timing out**
```dart
test('slow test', () async {
  // Increase timeout
}, timeout: Timeout(Duration(minutes: 2)));
```

**Issue: Platform-specific test failures**
```dart
test('platform test', () {
  // Skip on specific platforms
  if (Platform.isAndroid) {
    // Android-specific test
  }
}, skip: !Platform.isAndroid);
```

**Issue: Flaky tests**
- Use `pumpAndSettle()` for widget tests
- Add proper async/await
- Check for race conditions
- Use mocks to eliminate network calls

## Resources

- [Flutter Testing Documentation](https://docs.flutter.dev/testing)
- [Effective Dart: Testing](https://dart.dev/guides/language/effective-dart/testing)
- [Test Package Documentation](https://pub.dev/packages/test)
- [Mockito for Flutter](https://pub.dev/packages/mockito)

## Support

For questions about testing:
1. Check existing test examples
2. Review this guide
3. Open an issue on GitHub
4. Contact the development team

---

**Test Coverage:** 578 tests passing in the Dart layer; **no automated native tests yet**
**Status:** Active development — native layers need on-device verification
**Last Updated:** June 22, 2026
