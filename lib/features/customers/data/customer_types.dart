import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../shared/services/authed_api.dart';
import '../../auth/domain/permissions.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../parties/data/parties_repository.dart';
import '../../parties/domain/party.dart';

/// A kind of customer (Retail, Wholesale, ...), as `/api/v1/customer-types`
/// returns it. [defaultCreditLimit] is suggested for new customers of the
/// type.
class CustomerType {
  const CustomerType({
    required this.id,
    required this.name,
    this.defaultCreditLimit = 0,
    this.defaultPaymentTermsDays = 30,
    this.customerCount = 0,
  });

  final String id;
  final String name;
  final double defaultCreditLimit;
  final int defaultPaymentTermsDays;

  /// Customers of this type, archived ones included.
  final int customerCount;

  factory CustomerType.fromJson(Map<String, dynamic> json) => CustomerType(
        id: json['id'] as String,
        name: json['name'] as String,
        defaultCreditLimit: (json['defaultCreditLimit'] as num?)?.toDouble() ?? 0,
        defaultPaymentTermsDays: (json['defaultPaymentTermsDays'] as num?)?.toInt() ?? 30,
        customerCount: (json['customerCount'] as num?)?.toInt() ?? 0,
      );
}

/// REAL `/api/v1/customer-types`. Reading falls back to the saved copy
/// offline; changing the list needs a connection.
class CustomerTypesRepository {
  CustomerTypesRepository(this._api);

  final AuthedApi _api;

  Future<List<CustomerType>> list() async {
    final json = await _api.get(ApiConstants.customerTypes, cacheKey: 'customer_types');
    return [
      for (final row in (json['customerTypes'] as List<dynamic>? ?? const []))
        CustomerType.fromJson(row as Map<String, dynamic>),
    ];
  }

  Future<CustomerType> create(String name, {double defaultCreditLimit = 0, int defaultPaymentTermsDays = 30}) async {
    final json = await _api.post(ApiConstants.customerTypes, {
      'name': name,
      'defaultCreditLimit': defaultCreditLimit,
      'defaultPaymentTermsDays': defaultPaymentTermsDays,
    });
    return CustomerType.fromJson(json['customerType'] as Map<String, dynamic>);
  }

  Future<CustomerType> update(String id, {String? name, double? defaultCreditLimit, int? defaultPaymentTermsDays}) async {
    final json = await _api.patch(ApiConstants.customerType(id), {
      'name': ?name,
      'defaultCreditLimit': ?defaultCreditLimit,
      'defaultPaymentTermsDays': ?defaultPaymentTermsDays,
    });
    return CustomerType.fromJson(json['customerType'] as Map<String, dynamic>);
  }

  Future<void> delete(String id) => _api.delete(ApiConstants.customerType(id));
}

final customerTypesRepositoryProvider = Provider<CustomerTypesRepository>(
  (ref) => CustomerTypesRepository(ref.watch(authedApiProvider)),
);

class CustomerTypesNotifier extends AsyncNotifier<List<CustomerType>> {
  @override
  Future<List<CustomerType>> build() async {
    if (ref.watch(sessionUserIdProvider) == null) return const [];
    if (!ref.watch(holdsPermissionProvider(Permissions.customersView))) return const [];
    return ref.watch(customerTypesRepositoryProvider).list();
  }

  Future<void> refresh() async {
    if (!ref.read(holdsPermissionProvider(Permissions.customersView))) return;
    state = await AsyncValue.guard(ref.read(customerTypesRepositoryProvider).list);
  }

  Future<CustomerType> add(String name, {double defaultCreditLimit = 0, int defaultPaymentTermsDays = 30}) async {
    final type = await ref
        .read(customerTypesRepositoryProvider)
        .create(name, defaultCreditLimit: defaultCreditLimit, defaultPaymentTermsDays: defaultPaymentTermsDays);
    await refresh();
    return type;
  }

  /// A rename shows on every customer of the type, so they are re-read too.
  Future<void> edit(String id, {String? name, double? defaultCreditLimit, int? defaultPaymentTermsDays}) async {
    await ref.read(customerTypesRepositoryProvider).update(
          id,
          name: name,
          defaultCreditLimit: defaultCreditLimit,
          defaultPaymentTermsDays: defaultPaymentTermsDays,
        );
    await Future.wait([refresh(), ref.read(partiesProvider(PartyType.customer).notifier).refresh()]);
  }

  Future<void> remove(String id) async {
    await ref.read(customerTypesRepositoryProvider).delete(id);
    await refresh();
  }
}

final customerTypesProvider =
    AsyncNotifierProvider<CustomerTypesNotifier, List<CustomerType>>(CustomerTypesNotifier.new);

/// The name to show for a customer's type: the current list first (so a
/// rename shows at once), then what the server sent with the customer.
final customerTypeNameProvider = Provider.family<String?, Party>((ref, customer) {
  final id = customer.customerTypeId;
  if (id == null) return null;
  final types = ref.watch(customerTypesProvider).valueOrNull ?? const <CustomerType>[];
  return types.where((t) => t.id == id).firstOrNull?.name ?? customer.customerTypeName;
});
