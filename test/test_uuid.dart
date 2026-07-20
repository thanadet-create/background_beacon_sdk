/// Shared fixture UUID for every test — default = the real fleet UUID
/// (same value as `example/config/dev.json`); run against another config with:
/// `flutter test --dart-define-from-file=example/config/dev.json`
const testFleetUuid = String.fromEnvironment(
  'BEACON_UUID',
  defaultValue: 'e2c56db5-dffb-48d2-b060-d0f5a71096e0',
);
