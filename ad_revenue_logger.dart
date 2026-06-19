import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_ads/ads_flutter.dart';
import 'package:flutter_iap/flutter_iap.dart';

import '../../../src/shared/helpers/logger_utils.dart';

/// Lắng nghe paid-event (impression-level ad revenue) do GMA SDK bắn ra
/// qua [AdEventsStream] của flutter_ads, rồi log lên Firebase Analytics
/// dưới event `paid_ad_impression` kèm doanh thu thực của từng impression.
///
/// Đây là dữ liệu giúp BigQuery query được doanh thu ad theo từng user
/// (user_pseudo_id / geo.country / platform được Firebase tự gắn vào event).
/// Doanh thu account-level từ AdMob↔Firebase link KHÔNG ghi value vào BigQuery,
/// nên bắt buộc phải tự log từ app như thế này.
class AdRevenueLogger {
  AdRevenueLogger._();

  static final AdRevenueLogger instance = AdRevenueLogger._();

  static const String eventName = 'paid_ad_impression';

  StreamSubscription<AdInformation>? _subscription;

  /// Gọi 1 lần sau khi Firebase đã init xong.
  void start() {
    if (_subscription != null) {
      return;
    }
    _subscription = AdEventsStream.instance.stream
        .where((e) => e.status.isPaid && e.valueMicros != null)
        .listen(
          _logPaidEvent,
          onError: (Object e) => logger.e(e),
        );
  }

  Future<void> _logPaidEvent(AdInformation e) async {
    final double valueUsd = (e.valueMicros ?? 0) / 1000000.0;
    // DEBUG: log mọi paid-event trước khi qua guard để verify callback có bắn.
    if (kDebugMode) {
      logger.i('[AdRevenue] paid ${e.type.name} '
          'value=$valueUsd ${e.currencyCode} unit=${e.adId} '
          'premium=${purchasesManager.isPremium}');
    }
    if (valueUsd <= 0) {
      return;
    }
    try {
      await FirebaseAnalytics.instance.logEvent(
        name: eventName,
        parameters: {
          'value': valueUsd,
          'currency': e.currencyCode ?? 'USD',
          'ad_format': e.type.name,
          'ad_unit_id': e.adId,
          'ad_key': e.adKey ?? '',
          'precision': e.precision?.name ?? '',
        },
      );
    } catch (err) {
      logger.e(err);
    }
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
