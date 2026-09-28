import '../../../shared/offline/outbox.dart';
import '../domain/party.dart';

/// The server's parties with every change still waiting in the outbox applied
/// on top, so a customer or payment recorded offline shows at once (and simply
/// stops being an overlay once it has synced and the server data includes it).
///
/// Ops the server refused are left out — they didn't happen. Credit entries
/// adjust the balance of their party, including one created offline (its
/// `local:<id>` id).
List<Party> overlayParties(List<Party> base, List<OutboxOp> ops, PartyType type) {
  final parties = [...base];
  int indexOf(String id) => parties.indexWhere((p) => p.id == id);

  for (final op in ops) {
    if (op.failed) continue;
    switch (op.kind) {
      case OpKind.partyCreate:
        if (PartyTypeX.fromApi(op.payload['type'] as String) != type) continue;
        parties.add(
          PartyInput.fromJson(type, Map<String, dynamic>.from(op.payload['input'] as Map))
              .toLocalParty(op.localId),
        );
      case OpKind.partyUpdate:
        if (PartyTypeX.fromApi(op.payload['type'] as String) != type) continue;
        final i = indexOf(op.payload['id'] as String);
        if (i >= 0) {
          parties[i] = parties[i].withInput(
            PartyInput.fromJson(type, Map<String, dynamic>.from(op.payload['input'] as Map)),
          );
        }
      case OpKind.partyArchive:
        if (PartyTypeX.fromApi(op.payload['type'] as String) != type) continue;
        final i = indexOf(op.payload['id'] as String);
        if (i >= 0) parties.removeAt(i);
      case OpKind.creditEntry:
        if (PartyTypeX.fromApi(op.payload['partyType'] as String) != type) continue;
        final i = indexOf(op.payload['partyId'] as String);
        if (i >= 0) {
          final signed = signedCreditAmount(
            CreditKindX.fromApi(op.payload['kind'] as String),
            (op.payload['amount'] as num).toDouble(),
          );
          parties[i] = parties[i].copyWith(balanceOwed: parties[i].balanceOwed + signed);
        }
      case OpKind.movement:
      case OpKind.productCreate:
      case OpKind.productUpdate:
      case OpKind.productArchive:
        break;
    }
  }

  return parties;
}

/// The credit entries still waiting to sync for one party, newest first,
/// shaped like ledger rows (marked pending).
List<CreditEntry> pendingCreditEntries(List<OutboxOp> ops, String partyId) {
  final entries = <CreditEntry>[];
  for (final op in ops) {
    if (op.failed || op.kind != OpKind.creditEntry) continue;
    if (op.payload['partyId'] != partyId) continue;
    final kind = CreditKindX.fromApi(op.payload['kind'] as String);
    entries.add(
      CreditEntry(
        id: 'pending:${op.id}',
        partyType: PartyTypeX.fromApi(op.payload['partyType'] as String),
        partyId: partyId,
        kind: kind,
        amount: signedCreditAmount(kind, (op.payload['amount'] as num).toDouble()),
        note: op.payload['note'] as String?,
        createdAt: op.createdAt,
        isPending: true,
      ),
    );
  }
  entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return entries;
}
