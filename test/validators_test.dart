import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_form_app/screens/form_screen.dart';
import 'package:offline_form_app/utils/validators.dart';

void main() {
  group('Validators.fullName', () {
    test('empty name is rejected', () {
      expect(Validators.fullName(''), 'Please enter full name');
      expect(Validators.fullName('   '), 'Please enter full name');
      expect(Validators.fullName(null), 'Please enter full name');
    });

    test('name shorter than 3 letters is rejected', () {
      expect(Validators.fullName('Al'), 'Name must be at least 3 characters');
    });

    test('valid name is accepted', () {
      expect(Validators.fullName('Asha Kumar'), isNull);
    });
  });

  group('Validators.mobile', () {
    test('empty mobile is rejected', () {
      expect(Validators.mobile(''), 'Please enter mobile number');
    });

    test('mobile must be exactly 10 digits', () {
      const error = 'Mobile number must be exactly 10 digits';
      expect(Validators.mobile('12345'), error);
      expect(Validators.mobile('98765432101'), error);
      expect(Validators.mobile('98765abcde'), error);
    });

    test('10-digit mobile is accepted', () {
      expect(Validators.mobile('9876543210'), isNull);
    });
  });

  group('Validators.email', () {
    test('empty email is rejected', () {
      expect(Validators.email(''), 'Please enter email');
    });

    test('badly formed email is rejected', () {
      const error = 'Please enter a valid email';
      expect(Validators.email('asha'), error);
      expect(Validators.email('asha@'), error);
      expect(Validators.email('asha@mail'), error);
    });

    test('valid email is accepted', () {
      expect(Validators.email('asha.k@mail.com'), isNull);
    });
  });

  group('Validators.requiredField', () {
    test('uses the field name in the message', () {
      expect(
        Validators.requiredField('', 'description'),
        'Please enter description',
      );
      expect(Validators.requiredField('Some text', 'description'), isNull);
    });
  });

  group('Validators.serverUrl', () {
    test('needs http:// and a host', () {
      expect(Validators.serverUrl(''), isNotNull);
      expect(Validators.serverUrl('192.168.1.5:3000'), isNotNull);
      expect(Validators.serverUrl('http://'), isNotNull);
      expect(Validators.serverUrl('http://192.168.1.5:3000'), isNull);
    });
  });

  testWidgets('tapping Save on an empty form shows every error', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: FormScreen()));

    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Please enter full name'), findsOneWidget);
    expect(find.text('Please enter mobile number'), findsOneWidget);
    expect(find.text('Please enter email'), findsOneWidget);
    expect(find.text('Please select a category'), findsOneWidget);
    expect(find.text('Please enter description'), findsOneWidget);
    expect(find.text('Please select visit date'), findsOneWidget);
    expect(find.text('Please select an image'), findsOneWidget);
  });
}
