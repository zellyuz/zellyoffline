import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../../models/order.dart';
import '../../database_helper.dart';
import '../../printing_service.dart';
import '../../services/inventory_service.dart';
import '../api_context.dart';
import '../websocket_manager.dart';

/// `/print_job`, `/print_receipt` — mijoz qurilmalari serverning
/// printerlarida chop etadi. `/print_job` ayni paytda ombor qoldig'ini ham
/// chegiradi (qoldiq yetmasa 409).
class PrintRoutes {
  const PrintRoutes._();

  static void register(Router router) {
    // Remote print job — client devices POST here so server prints on its printers
    router.post('/print_job', (Request request) async {
      try {
        final body = await request.readAsString();
        final Map<String, dynamic> payload =
            Map<String, dynamic>.from(jsonDecode(body) as Map);
        final order = Order.fromPrintPayload(payload);

        // §8 — buyurtma tasdiqlanganda tayyor mahsulot qoldig'i chegiriladi.
        // Client qurilmada baza yo'q, shuning uchun tekshiruv shu yerda.
        // Qoldiq yetmasa chek chop etilmaydi va 409 qaytadi.
        if (await ApiContext.inventoryEnabled()) {
          try {
            await InventoryService.instance.consumeOnConfirm(
              order.id,
              order.items
                  .map((i) => (productId: i.productId, qty: i.qty.toDouble()))
                  .toList(),
            );
          } on InsufficientStockException catch (e) {
            return Response(409,
                body: jsonEncode({'error': e.message, 'insufficient': true}),
                headers: {'Content-Type': 'application/json'});
          }
        }

        await PrintingService.printDividedOrder(order: order);
        return Response.ok(jsonEncode({'ok': true}),
            headers: {'Content-Type': 'application/json'});
      } catch (e) {
        debugPrint('[print_job] Error: $e');
        return Response.internalServerError(
            body: jsonEncode({'error': e.toString()}));
      }
    });


    // Remote receipt print — client devices POST here to print main receipt on server
    router.post('/print_receipt', (Request request) async {
      final denied = ApiContext.requirePermission(request, 'print_receipt');
      if (denied != null) return denied;
      try {
        final body = await request.readAsString();
        final Map<String, dynamic> payload =
            Map<String, dynamic>.from(jsonDecode(body) as Map);

        final orderId = payload['id'] as String?;
        if (orderId == null || orderId.isEmpty) {
          return Response.badRequest(
              body: jsonEncode({'error': 'order id yuborilmadi'}));
        }

        final db = await DatabaseHelper.instance.database;
        Order order;
        bool orderInDb = false;
        dynamic tableId;

        // 1. Order DB da bor-yo'qligini tekshiramiz
        final orderRows = await db.rawQuery('''
          SELECT o.*,
            t.name as table_name, t.pricing_type, t.hourly_rate,
            t.fixed_amount, t.service_percentage,
            l.name as location_name,
            w.name as waiter_name, w.type as waiter_type, w.value as waiter_value
          FROM orders o
          LEFT JOIN tables t ON o.table_id = t.id
          LEFT JOIN locations l ON o.location_id = l.id
          LEFT JOIN waiters w ON o.waiter_id = w.id
          WHERE o.id = ?
        ''', [orderId]);

        if (orderRows.isNotEmpty) {
          // DB da bor — DB dan to'liq ma'lumot olamiz
          orderInDb = true;
          final orderMap = Map<String, dynamic>.from(orderRows.first);
          tableId = orderMap['table_id'];

          final itemRows = await db.rawQuery('''
            SELECT oi.*, p.name as product_name, p.no_service_charge,
                   p.category as category_id
            FROM order_items oi
            JOIN products p ON oi.product_id = p.id
            WHERE oi.order_id = ?
          ''', [orderId]);

          final items = itemRows.map((r) => OrderItem.fromMap(
            Map<String, dynamic>.from(r),
            productName: r['product_name'] as String? ?? '',
          )).toList();

          // Xona/stol narxini hisoblash
          double roomCharge = (orderMap['room_charge'] as num?)?.toDouble() ?? 0;
          if (roomCharge == 0 && orderMap['pricing_type'] != null) {
            final pricingType = orderMap['pricing_type'] as int? ?? 0;
            final openedAt = orderMap['opened_at'] != null
                ? DateTime.tryParse(orderMap['opened_at'] as String)
                : null;
            if (pricingType == 1 && openedAt != null) {
              final hours = DateTime.now().difference(openedAt).inMinutes / 60.0;
              final hourlyRate = (orderMap['hourly_rate'] as num?)?.toDouble() ?? 0;
              roomCharge = (hours * hourlyRate).roundToDouble();
            } else if (pricingType == 2) {
              roomCharge = (orderMap['fixed_amount'] as num?)?.toDouble() ?? 0;
            } else if (pricingType == 3) {
              final pct = (orderMap['service_percentage'] as num?)?.toDouble() ?? 0;
              final foodTotal = items
                  .where((i) => i.productName != 'noServiceCharge')
                  .fold(0.0, (sum, i) => sum + i.qty * i.price);
              roomCharge = (foodTotal * pct / 100).roundToDouble();
            }
          }

          // Ofisant xizmat haqi hisoblash
          double serviceTotal = (orderMap['service_total'] as num?)?.toDouble() ?? 0;
          if (serviceTotal == 0 &&
              orderMap['waiter_type'] != null &&
              orderMap['waiter_name'] != 'Kassa') {
            final waiterType = orderMap['waiter_type'] as int? ?? 0;
            final waiterValue = (orderMap['waiter_value'] as num?)?.toDouble() ?? 0;
            if (waiterType == 1 && waiterValue > 0) {
              final taxableTotal = items
                  .fold(0.0, (sum, i) => sum + i.qty * i.price);
              serviceTotal = (taxableTotal * waiterValue / 100).roundToDouble();
            } else if (waiterType == 0 && waiterValue > 0) {
              serviceTotal = waiterValue;
            }
          }

          orderMap['room_charge']   = roomCharge;
          orderMap['room_total']    = roomCharge;
          orderMap['service_total'] = serviceTotal;
          orderMap['grand_total']   =
              ((orderMap['total'] as num?)?.toDouble() ?? 0) + roomCharge + serviceTotal;
          orderMap['table_name']    = payload['table_name'] ?? orderMap['table_name'];
          orderMap['location_name'] = payload['location_name'] ?? orderMap['location_name'];
          orderMap['waiter_name']   = payload['waiter_name'] ?? orderMap['waiter_name'];

          order = Order.fromMap(orderMap, items: items);
        } else {
          // DB da yo'q — vaqtinchalik chek (offisant yangi buyurtma qo'shmoqda)
          // Payload da barcha kerakli ma'lumot bor (toPrintPayload() dan keladi)
          order = Order.fromPrintPayload(payload);
          tableId = payload['table_id'];
          debugPrint('[print_receipt] Vaqtinchalik chek — payload dan print: $orderId');
        }

        // bill_requested faqat DB da bor orderlar uchun
        if (orderInDb) {
          await db.update(
            'orders',
            {
              'bill_requested': 1,
              'bill_requested_at': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [orderId],
          );
          if (tableId != null) {
            WebSocketManager.instance.broadcast('tables_updated', {'table_id': tableId});
          }
        }

        // Serverning o'z printeri orqali chop etamiz
        await PrintingService.printReceipt(order: order);

        return Response.ok(jsonEncode({'ok': true}),
            headers: {'Content-Type': 'application/json'});
      } catch (e, st) {
        debugPrint('[print_receipt] Error: $e\n$st');
        return Response.internalServerError(
            body: jsonEncode({'error': e.toString()}));
      }
    });

  }
}
