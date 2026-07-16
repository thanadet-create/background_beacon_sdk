/// UUID กลางของ fixture ทุก test — default = fleet UUID จริง
/// (ค่าเดียวกับ `example/config/dev.json`) จะรันให้ตรง config อื่นก็ได้:
/// `flutter test --dart-define-from-file=example/config/dev.json`
const testFleetUuid = String.fromEnvironment(
  'BEACON_UUID',
  defaultValue: 'e2c56db5-dffb-48d2-b060-d0f5a71096e0',
);
