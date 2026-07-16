import 'package:flutter_test/flutter_test.dart';

import 'package:background_beacon_sdk_example/main.dart';

void main() {
  testWidgets('renders test controls', (tester) async {
    await tester.pumpWidget(const ExampleApp());

    // แค่ smoke test ว่า UI ขึ้นครบ — flow จริง (auto-start) ต้อง native
    // จึงทดสอบบน device (ปุ่มหยุด/เริ่ม scan ไม่มีแล้ว — ทุกอย่าง auto)
    expect(find.text('Detect once'), findsOneWidget);
  });
}
