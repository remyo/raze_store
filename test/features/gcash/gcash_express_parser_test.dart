import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/features/gcash/gcash_parser.dart';
import 'package:raze_store/features/gcash/gcash_record.dart';

// Synthetic identities and reference numbers; no customer screenshot data.
String expressReceipt({
  String name = 'JU•• D••',
  String phone = '+63 917 000 0000',
  String amount = '1,000.00',
  String? total,
  String footer = 'Ref No. 0040000000001 Jun 27, 2026 6:02 PM',
}) =>
    '''16:19
Express Send
$name
$phone
Sent via GCash
Amount
$amount
Total Amount Sent
₱${total ?? amount}
$footer
You saved 279g of carbon emissions
Send Again
Download
Back to Home''';

void main() {
  group('Express Send receipt suggestions', () {
    for (final sample in [
      ('1,000.00', 100000),
      ('10,000.00', 1000000),
      ('3,200.00', 320000),
      ('21,300.00', 2130000),
    ]) {
      test('reads currency-free Amount ${sample.$1}', () {
        final result = parseGcashReceipt(
          expressReceipt(amount: sample.$1),
          GcashKind.cashIn,
        );
        expect(result.name, 'JU•• D••');
        expect(result.number, '+63 917 000 0000');
        expect(result.amount, sample.$2);
        expect(result.reference, '0040000000001');
        expect(result.date, DateTime(2026, 6, 27, 18, 2));
        expect(result.isGcashReceipt, isTrue);
        expect(result.recipientOnly, isFalse);
      });
    }

    test('Cash Out preserves transfer fields but needs the sender', () {
      final result = parseGcashReceipt(expressReceipt(), GcashKind.cashOut);
      expect(result.name, isNull);
      expect(result.number, isNull);
      expect(result.amount, 100000);
      expect(result.reference, '0040000000001');
      expect(result.date, DateTime(2026, 6, 27, 18, 2));
      expect(result.recipientOnly, isTrue);
    });

    test('a sender name does not make the recipient phone a sender phone', () {
      final result = parseGcashReceipt(
        '${expressReceipt()}\nSender: MA•• T••',
        GcashKind.cashOut,
      );
      expect(result.name, 'MA•• T••');
      expect(result.number, isNull);
      expect(result.recipientOnly, isFalse);
    });

    test('explicit sender fields remain usable on an Express receipt', () {
      final result = parseGcashReceipt(
        '${expressReceipt()}\nSender: MA•• T••\nSender mobile number: 09180000000',
        GcashKind.cashOut,
      );
      expect(result.name, 'MA•• T••');
      expect(result.number, '09180000000');
      expect(result.recipientOnly, isFalse);
    });

    test('Cash Out stays conservative when OCR misses Sent via GCash', () {
      final result = parseGcashReceipt(
        expressReceipt().replaceFirst('Sent via GCash', 'GCash'),
        GcashKind.cashOut,
      );
      expect(result.name, isNull);
      expect(result.number, isNull);
      expect(result.recipientOnly, isTrue);
    });

    test('cropped header and failed name OCR still mark recipient-only', () {
      final result = parseGcashReceipt(
        expressReceipt()
            .replaceFirst('Express Send\n', '')
            .replaceFirst('JU•• D••\n', ''),
        GcashKind.cashOut,
      );
      expect(result.name, isNull);
      expect(result.number, isNull);
      expect(result.recipientOnly, isTrue);
    });

    test('Express Send identifies recipient even when GCash OCR fails', () {
      final result = parseGcashReceipt(
        expressReceipt().replaceFirst('Sent via GCash', 'Sent via GCa5h'),
        GcashKind.cashOut,
      );
      expect(result.name, isNull);
      expect(result.number, isNull);
      expect(result.recipientOnly, isTrue);
      expect(result.isGcashReceipt, isFalse);
      expect(result.reference, '0040000000001');
    });

    for (final phone in [
      '+63 9xx xxx xxxx',
      '+63 9•• ••• ••••',
      '+63-917-000-0000',
      '+639170000000',
      '09*****0000',
      '09170000000',
    ]) {
      test('retains the original phone formatting and masks: $phone', () {
        final result = parseGcashReceipt(
          expressReceipt(phone: phone),
          GcashKind.cashIn,
        );
        expect(result.name, 'JU•• D••');
        expect(result.number, phone);
      });
    }

    test('a joined name and phone remains tied to Sent via GCash', () {
      final result = parseGcashReceipt(
        expressReceipt().replaceFirst('JU•• D••\n+', 'JU•• D•• +'),
        GcashKind.cashIn,
      );
      expect(result.name, 'JU•• D••');
      expect(result.number, '+63 917 000 0000');
    });

    test('multiple different phones leave unlabelled identity unresolved', () {
      final result = parseGcashReceipt(
        '${expressReceipt()}\n09180000000',
        GcashKind.cashIn,
      );
      expect(result.name, isNull);
      expect(result.number, isNull);
    });

    test('conflicting names beside a repeated phone remain unresolved', () {
      final result = parseGcashReceipt(
        '${expressReceipt()}\nMA•• T••\n+63 917 000 0000\nSent via GCash',
        GcashKind.cashIn,
      );
      expect(result.name, isNull);
      expect(result.number, '+63 917 000 0000');
    });

    test('conflicting recipient labels cannot fall back to a masked name', () {
      final result = parseGcashReceipt(
        '${expressReceipt()}\nRecipient: AB•• C••\nRecipient: DE•• F••',
        GcashKind.cashIn,
      );
      expect(result.name, isNull);
    });

    test('repeated equivalent phone formats do not create ambiguity', () {
      final result = parseGcashReceipt(
        '${expressReceipt()}\n09170000000',
        GcashKind.cashIn,
      );
      expect(result.name, 'JU•• D••');
      expect(result.number, '+63 917 000 0000');
    });

    test('without receipt markers an unlabelled name is not inferred', () {
      final result = parseGcashReceipt(
        'JU•• D••\n+63 917 000 0000\nAmount 1,000.00',
        GcashKind.cashIn,
      );
      expect(result.name, isNull);
      expect(result.isGcashReceipt, isFalse);
      expect(result.recipientOnly, isFalse);
    });

    test('transfer amount wins over a total that includes a service fee', () {
      final result = parseGcashReceipt(
        expressReceipt(total: '1,010.00').replaceFirst(
          'Total Amount Sent',
          'Service fee ₱10.00\nTotal Amount Sent',
        ),
        GcashKind.cashIn,
      );
      expect(result.amount, 100000);
    });

    test('joined amount and total still use the amount label', () {
      final result = parseGcashReceipt(
        'GCash\nAmount 1,000.00 Total Amount Sent ₱1,010.00',
        GcashKind.cashIn,
      );
      expect(result.amount, 100000);
    });

    test(
      'missing transfer amount does not substitute total or carbon copy',
      () {
        final result = parseGcashReceipt(
          expressReceipt().replaceFirst('Amount\n1,000.00\n', ''),
          GcashKind.cashIn,
        );
        expect(result.amount, isNull);
      },
    );

    test('invalid or conflicting labelled amounts remain empty', () {
      for (final raw in [
        'GCash\nAmount 1,000.001\nTotal ₱1,000.00',
        'GCash\nAmount 1,000.00\nAmount 2,000.00',
      ]) {
        expect(parseGcashReceipt(raw, GcashKind.cashIn).amount, isNull);
      }
    });

    for (final footer in [
      'Ref No. 0040000000001 Jun 27, 2026 6:02 PM',
      'Ref No. 0040000000001June 27, 2026 6:02PM',
      'Ref No. 0040000000001 June 27,2026 6:02PM',
      'Ref No.\n0040000000001\nJune 27, 2026 6:02 PM',
      'Ref No. 0040000000001\nJune 27, 2026\n6:02 PM',
      'Ref No.\nJune 27, 2026 6:02 PM\n0040000000001',
      'Ref No. June 27, 2026 6:02 PM\n0040000000001',
      'June 27, 2026\n6:02 PM\nRef No.\n0040000000001',
      'Ref No. 0040 000 000001 | June 27, 2026 6:02 PM',
    ]) {
      test('reads footer ordering: ${footer.replaceAll('\n', ' / ')}', () {
        final result = parseGcashReceipt(
          expressReceipt(footer: footer),
          GcashKind.cashIn,
        );
        expect(result.reference, '0040000000001');
        expect(result.date, DateTime(2026, 6, 27, 18, 2));
      });
    }

    test('status-bar time cannot replace a missing receipt date', () {
      final result = parseGcashReceipt(
        expressReceipt(footer: 'Ref No. 0040000000001'),
        GcashKind.cashIn,
      );
      expect(result.date, isNull);
      expect(result.reference, '0040000000001');
    });

    for (final headerVisible in [true, false]) {
      test(
        'missing reference rejects promotional copy; header=$headerVisible',
        () {
          for (final nextLine in [
            '279g',
            'gCO2e',
            '(gCO2e)',
            'You saved 279g of carbon emissions',
            'Send Again',
          ]) {
            var text = expressReceipt(
              footer: 'Ref No. Jun 27, 2026 6:02 PM\n$nextLine',
            );
            if (!headerVisible) {
              text = text.replaceFirst('Express Send\n', '');
            }
            final result = parseGcashReceipt(text, GcashKind.cashIn);
            expect(result.reference, isNull, reason: nextLine);
            expect(result.date, DateTime(2026, 6, 27, 18, 2));
          }
        },
      );
    }

    test('Express references accept multiple long numeric lengths', () {
      for (final reference in [
        '00400001',
        '004000000001',
        '0040000000001',
        '00400000000001',
      ]) {
        final result = parseGcashReceipt(
          expressReceipt(footer: 'Ref No. $reference'),
          GcashKind.cashIn,
        );
        expect(result.reference, reference);
      }
      final shortReference = parseGcashReceipt(
        expressReceipt(footer: 'Ref No. 0000279'),
        GcashKind.cashIn,
      );
      expect(shortReference.reference, isNull);
    });

    test('other labelled receipts retain their alphanumeric references', () {
      final result = parseGcashReceipt(
        'GCash\nFrom: MA•• T••\nTransaction ID: TEST1234',
        GcashKind.cashOut,
      );
      expect(result.reference, 'TEST1234');
    });

    test('different explicit dates and references remain ambiguous', () {
      final result = parseGcashReceipt(
        '${expressReceipt()}\nRef No. 0040000000002 Jul 1, 2026 8:10 AM',
        GcashKind.cashIn,
      );
      expect(result.date, isNull);
      expect(result.reference, isNull);
    });

    test('invalid calendar dates are not normalized into another day', () {
      final result = parseGcashReceipt(
        expressReceipt(footer: 'Ref No. 0040000000001 Feb 30, 2026 6:02 PM'),
        GcashKind.cashIn,
      );
      expect(result.date, isNull);
    });
  });
}
