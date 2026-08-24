import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../../models/order.dart';
import '../../app_logger.dart';
import '../../database_helper.dart';
import '../../services/inventory_service.dart';
import '../api_context.dart';
import '../websocket_manager.dart';

/// `/orders/*` va `/tables/merge` — POS ning asosiy oqimi:
/// buyurtma ochish, savatni sinxronlash, ko'chirish, to'lash, bekor qilish.
class OrderRoutes {
  const OrderRoutes._();

  static void register(Router router) {
    router.post('/orders/open', (Request request) async {
      try {
        final payload = jsonDecode(await request.readAsString());
        final tableId = payload['table_id'] as int?;

        // waiter_id tokendan olinadi — mijoz uni o'zi tanlay olmaydi.
        final session = ApiContext.sessionOf(request);
        final waiterId = session != null && session.isWaiter
            ? session.userId
            : (payload['waiter_id'] as int? ?? 1);

        final orderType = payload['order_type'] as int? ?? 0;
        final db = await DatabaseHelper.instance.database;

        // Check if table already has open order (only for dine-in)
        if (tableId != null) {
          final existing = await db.query(
            'orders',
            where: 'table_id = ? AND status = 0',
            whereArgs: [tableId],
          );

          if (existing.isNotEmpty) {
            final orderId = existing.first['id'];
            final dailyNo = existing.first['daily_number'];
            return Response.ok(jsonEncode({
              'order_id': orderId,
              'daily_number': dailyNo,
              'status': 'existing'
            }));
          }
        }

        final orderId = DateTime.now().millisecondsSinceEpoch.toString();

        final dayStart = await DatabaseHelper.instance.getDayStartTime();

        int nextNo = 1;
        final res = await db.rawQuery(
          'SELECT MAX(daily_number) as max_no FROM orders WHERE created_at >= ?',
          [dayStart.toIso8601String()],
        );
        if (res.isNotEmpty && res.first['max_no'] != null) {
          nextNo = (res.first['max_no'] as int) + 1;
        }

        await db.transaction((txn) async {
          await txn.insert('orders', {
            'id': orderId,
            'total': 0.0,
            'payment_type': 'Pending',
            'created_at': DateTime.now().toIso8601String(),
            'order_type': orderType,
            'table_id': tableId,
            'waiter_id': waiterId,
            'status': 0,
            'opened_at': DateTime.now().toIso8601String(),
            'daily_number': nextNo,
          });

          if (tableId != null) {
            await txn.update(
              'tables',
              {'status': 1, 'active_order_id': orderId},
              where: 'id = ?',
              whereArgs: [tableId],
            );
          }
        });

        WebSocketManager.instance.broadcast('tables_updated', {
          'table_id': ?tableId,
        });

        return Response.ok(jsonEncode({
          'order_id': orderId,
          'daily_number': nextNo
        }));
      } catch (e, st) {
        debugPrint('[orders/open] ERROR: $e\n$st');
        return Response.internalServerError(body: 'orders/open error: $e');
      }
    });

    router.get('/orders/<id>', (Request request, String id) async {
      final db = await DatabaseHelper.instance.database;
      final orders = await db.query(
        'orders',
        where: 'id = ?',
        whereArgs: [id.toString()],
        limit: 1,
      );
      if (orders.isEmpty) return Response.notFound('Order not found');

      final items = await db.rawQuery(
        '''
        SELECT oi.*, p.name as product_name, p.no_service_charge, p.category as category_id
        FROM order_items oi
        JOIN products p ON oi.product_id = p.id
        WHERE oi.order_id = ?
      ''',
        [id.toString()],
      );

      var order = Map<String, dynamic>.from(orders.first);
      order['items'] = items;
      return Response.ok(jsonEncode(order));
    });

    router.post('/orders/<id>/items', (Request request, String id) async {
      final payload = jsonDecode(await request.readAsString());
      final items = payload['items'] as List;

      final db = await DatabaseHelper.instance.database;

      // Permission check: Get order and verify waiter_id
      final orders = await db.query(
        'orders',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (orders.isEmpty) {
        return Response.notFound('Order not found');
      }

      final order = orders.first;
      final orderWaiterId = order['waiter_id'] as int?;

      // Kim so'rayapti — sessiyadan aniqlanadi (mijoz alday olmaydi).
      final session = ApiContext.sessionOf(request);
      final currentWaiterId = session != null && session.isWaiter
          ? session.userId
          : null;
      final isAdmin = session != null && !session.isWaiter;

      // Check permission: only order owner or admin can modify
      if (!isAdmin && orderWaiterId != currentWaiterId) {
        return Response.forbidden(
          jsonEncode({
            'error': 'Bu stol sizga biriktirilmagan. Tahrirlash mumkin emas.',
          }),
        );
      }

      // Preserve existing printed_qty — never allow it to decrease (race condition guard)
      final existingItems = await db.query(
        'order_items',
        where: 'order_id = ?',
        whereArgs: [id],
      );
      final Map<int, double> existingPrintedQty = {
        for (var row in existingItems)
          (row['product_id'] as int): (row['printed_qty'] as num?)?.toDouble() ?? 0.0,
      };

      await db.transaction((txn) async {
        await txn.delete('order_items', where: 'order_id = ?', whereArgs: [id]);

        double totalAmount = 0;
        double totalForServiceCharge = 0;

        for (var item in items) {
          final double price = (item['price'] as num).toDouble();
          final double qty = (item['qty'] as num).toDouble();
          final int productId = item['product_id'] as int;
          final String? productName = item['product_name'] as String?;

          totalAmount += price * qty;

          final prodRes = await txn.query(
            'products',
            columns: ['no_service_charge'],
            where: 'id = ?',
            whereArgs: [productId],
          );
          bool noServiceCharge = false;
          if (prodRes.isNotEmpty) {
            noServiceCharge = (prodRes.first['no_service_charge'] as int? ?? 0) == 1;
          }

          if (!noServiceCharge) {
            totalForServiceCharge += price * qty;
          }

          final double newPrintedQty = (item['printed_qty'] as num?)?.toDouble() ?? 0.0;
          // Never decrease printed_qty — use the higher value to avoid race condition
          final double safePrintedQty = newPrintedQty > (existingPrintedQty[productId] ?? 0.0)
              ? newPrintedQty
              : (existingPrintedQty[productId] ?? 0.0);

          await txn.insert('order_items', {
            'order_id': id,
            'product_id': productId,
            'product_name': productName,
            'qty': qty,
            'price': price,
            'printed_qty': safePrintedQty,
          });
        }

        // Calculate Charges
        double roomCharge = 0;
        final orderData = orders.first;
        final int? tableId = orderData['table_id'] as int?;
        final int? orderType = orderData['order_type'] as int?;

        if (orderType == 0 && tableId != null) {
          // Dine-in: Calculate room charge from linked tables
          final List<Map<String, dynamic>> linkedTables = await txn.query(
            'tables',
            where: 'active_order_id = ? OR id = ?',
            whereArgs: [id, tableId],
          );

          double totalRoomCharge = 0;
          final DateTime now = DateTime.now();
          final DateTime openedAt = DateTime.tryParse(orderData['opened_at']?.toString() ?? '') ?? now;

          for (var tableMap in linkedTables) {
            final int pricingType = tableMap['pricing_type'] as int? ?? 0;
            final double hourlyRate = (tableMap['hourly_rate'] as num? ?? 0).toDouble();
            final double fixedAmount = (tableMap['fixed_amount'] as num? ?? 0).toDouble();
            final double servicePercentage = (tableMap['service_percentage'] as num? ?? 0).toDouble();

            if (pricingType == 1) {
              final duration = now.difference(openedAt);
              final hours = duration.inMinutes / 60.0;
              totalRoomCharge += hours * hourlyRate;
            } else if (pricingType == 2) {
              totalRoomCharge += fixedAmount;
            } else if (pricingType == 3) {
              totalRoomCharge += totalForServiceCharge * servicePercentage / 100;
            }
          }
          roomCharge = totalRoomCharge;
        }

        // Waiter Service Fee
        double serviceFee = 0;
        final int? waiterId = orderData['waiter_id'] as int?;
        if (waiterId != null) {
          final waiterRes = await txn.query('waiters', where: 'id = ?', whereArgs: [waiterId]);
          if (waiterRes.isNotEmpty) {
            final waiter = waiterRes.first;
            final String waiterName = waiter['name']?.toString() ?? '';
            final int waiterType = waiter['type'] as int? ?? 0;
            final double waiterValue = (waiter['value'] as num? ?? 0).toDouble();

            if (waiterName.toLowerCase() != 'kassa') {
              if (waiterType == 1) { // percentage
                serviceFee = (totalForServiceCharge * waiterValue / 100).roundToDouble();
              } else { // fixed
                serviceFee = waiterValue;
              }
            }
          }
        }

        final double grandTotal = totalAmount + roomCharge + serviceFee;

        await txn.update(
          'orders',
          {
            'total': grandTotal,
            'food_total': totalAmount,
            'room_charge': roomCharge,
            'room_total': roomCharge,
            'service_total': serviceFee,
            'grand_total': grandTotal,
            'waiter_id': payload['waiter_id'] ?? order['waiter_id'],
          },
          where: 'id = ?',
          whereArgs: [id.toString()],
        );
        AppLogger.d('ApiServer', 'API [POST] /orders/$id/items: Order total updated to $grandTotal');
      });

      WebSocketManager.instance.broadcast('order_updated', {'order_id': id});

      return Response.ok(jsonEncode({'status': 'success'}));
    });

    // Move order to another table
    router.put('/orders/<id>/move', (Request request, String id) async {
      final denied = ApiContext.requirePermission(request, 'change_table');
      if (denied != null) return denied;
      final payload = jsonDecode(await request.readAsString());
      final newTableId = payload['table_id'] as int?;
      final newLocationId = payload['location_id'] as int?;

      if (newTableId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'table_id required'}),
        );
      }

      final db = await DatabaseHelper.instance.database;

      final orders = await db.query(
        'orders',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (orders.isEmpty) return Response.notFound('Order not found');

      final oldTableId = orders.first['table_id'] as int?;

      await db.transaction((txn) async {
        // Update order
        final updateData = <String, dynamic>{'table_id': newTableId};
        if (newLocationId != null) updateData['location_id'] = newLocationId;
        await txn.update(
          'orders',
          updateData,
          where: 'id = ?',
          whereArgs: [id.toString()],
        );

        // Free old table
        if (oldTableId != null) {
          await txn.update(
            'tables',
            {'status': 0, 'active_order_id': null},
            where: 'id = ?',
            whereArgs: [oldTableId],
          );
        }

        // Occupy new table
        await txn.update(
          'tables',
          {'status': 1, 'active_order_id': id},
          where: 'id = ?',
          whereArgs: [newTableId],
        );
      });

      WebSocketManager.instance.broadcast('tables_updated');

      return Response.ok(jsonEncode({'status': 'success'}));
    });

    // Merge two tables' orders
    router.post('/tables/merge', (Request request) async {
      final payload = jsonDecode(await request.readAsString());
      final sourceTableId = payload['source_table_id'] as int?;
      final targetTableId = payload['target_table_id'] as int?;

      if (sourceTableId == null || targetTableId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'source_table_id and target_table_id required'}),
        );
      }

      final db = await DatabaseHelper.instance.database;

      final sourceRes = await db.query(
        'tables',
        where: 'id = ?',
        whereArgs: [sourceTableId],
      );
      final targetRes = await db.query(
        'tables',
        where: 'id = ?',
        whereArgs: [targetTableId],
      );

      if (sourceRes.isEmpty || targetRes.isEmpty) {
        return Response.notFound(jsonEncode({'error': 'Table not found'}));
      }

      final String? sourceOrderId =
          sourceRes.first['active_order_id'] as String?;
      final String? targetOrderId =
          targetRes.first['active_order_id'] as String?;

      if (sourceOrderId == null && targetOrderId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Both tables are empty'}),
        );
      }

      await db.transaction((txn) async {
        String finalOrderId;

        if (targetOrderId != null) {
          finalOrderId = targetOrderId;
          if (sourceOrderId != null && sourceOrderId != targetOrderId) {
            final sourceItems = await txn.query(
              'order_items',
              where: 'order_id = ?',
              whereArgs: [sourceOrderId],
            );
            for (var item in sourceItems) {
              final existing = await txn.query(
                'order_items',
                where: 'order_id = ? AND product_id = ?',
                whereArgs: [finalOrderId, item['product_id']],
              );
              if (existing.isNotEmpty) {
                final srcPrintedQty = item['printed_qty'] ?? item['qty'];
                await txn.rawUpdate(
                  'UPDATE order_items SET qty = qty + ?, printed_qty = printed_qty + ? WHERE id = ?',
                  [item['qty'], srcPrintedQty, existing.first['id']],
                );
              } else {
                await txn.insert('order_items', {
                  'order_id': finalOrderId,
                  'product_id': item['product_id'],
                  'qty': item['qty'],
                  'price': item['price'],
                  'printed_qty': item['printed_qty'] ?? item['qty'],
                });
              }
            }
            await txn.delete(
              'order_items',
              where: 'order_id = ?',
              whereArgs: [sourceOrderId],
            );
            await txn.delete(
              'orders',
              where: 'id = ?',
              whereArgs: [sourceOrderId],
            );
          }
        } else {
          finalOrderId = sourceOrderId!;
        }

        await txn.update(
          'tables',
          {'status': 1, 'active_order_id': finalOrderId},
          where: 'id = ? OR id = ?',
          whereArgs: [sourceTableId, targetTableId],
        );
      });

      return Response.ok(jsonEncode({'status': 'success'}));
    });

    router.post('/orders/<id>/pay', (Request request, String id) async {
      final payload = jsonDecode(await request.readAsString());
      final db = await DatabaseHelper.instance.database;

      // Get order data
      final orders = await db.query('orders', where: 'id = ?', whereArgs: [id], limit: 1);
      if (orders.isEmpty) return Response.notFound('Order not found');

      final orderData = Map<String, dynamic>.from(orders.first);
      final itemRows = await db.rawQuery(
        '''
        SELECT oi.*, p.quantity, p.track_type, p.is_set, p.image_path, p.no_service_charge, p.unit, p.name as product_name
        FROM order_items oi
        JOIN products p ON oi.product_id = p.id
        WHERE oi.order_id = ?
        ''',
        [id],
      );
      
      final List<OrderItem> orderItems = itemRows.map((row) => OrderItem.fromMap(row, productName: row['product_name'] as String? ?? '')).toList();
      final orderObj = Order.fromMap(orderData, items: orderItems);

      await db.transaction((txn) async {
        // Update order status and payment info
        await txn.update(
          'orders',
          {
            'status': 1, // Paid
            'payment_type': payload['payment_type'] ?? 'Cash',
            'paid_amount': (payload['paid_amount'] as num?)?.toDouble() ?? (payload['grand_total'] as num?)?.toDouble() ?? orderObj.total,
            'receipt_change': (payload['change'] as num?)?.toDouble() ?? 0.0,
            'closed_at': DateTime.now().toIso8601String(),
            'note': payload['note'],
            // Updates from client-calculated values
            'room_charge': (payload['room_charge'] as num?)?.toDouble() ?? orderObj.roomCharge,
            'room_total': (payload['room_charge'] as num?)?.toDouble() ?? orderObj.roomTotal,
            'service_total': (payload['service_total'] as num?)?.toDouble() ?? orderObj.serviceTotal,
            'food_total': (payload['food_total'] as num?)?.toDouble() ?? orderObj.foodTotal,
            'total': (payload['grand_total'] as num?)?.toDouble() ?? orderObj.total,
            'grand_total': (payload['grand_total'] as num?)?.toDouble() ?? orderObj.total,
            'waiter_id': payload['waiter_id'] ?? orderObj.waiterId,
          },
          where: 'id = ?',
          whereArgs: [id],
        );

        // If it was a table order, clear the table
        if (orderObj.tableId != null) {
          await txn.update(
            'tables',
            {'status': 0, 'active_order_id': null},
            where: 'id = ?',
            whereArgs: [orderObj.tableId],
          );
        }

        // --- CRITICAL: Process Inventory Deduction on Server ---
        await InventoryService.instance.processOrderPaid(orderObj, txn);
      });

      WebSocketManager.instance.broadcast('tables_updated');

      return Response.ok(jsonEncode({'status': 'success'}));
    });

    // Cancel empty order
    router.delete('/orders/<id>/cancel', (Request request, String id) async {
      final db = await DatabaseHelper.instance.database;

      // Get order
      final orders = await db.query(
        'orders',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (orders.isEmpty) {
        return Response.notFound('Order not found');
      }

      final order = orders.first;
      final orderWaiterId = order['waiter_id'] as int?;
      final tableId = order['table_id'] as int?;

      // Kim so'rayapti — sessiyadan aniqlanadi (mijoz alday olmaydi).
      final session = ApiContext.sessionOf(request);
      final currentWaiterId = session != null && session.isWaiter
          ? session.userId
          : null;
      final isAdmin = session != null && !session.isWaiter;

      // Check permission: only order owner or admin can cancel
      if (!isAdmin && orderWaiterId != currentWaiterId) {
        return Response.forbidden(
          jsonEncode({'error': 'Bu buyurtma sizga tegishli emas'}),
        );
      }

      // Allow cancelling with items if admin or cashier (if check passed above)
      // Original logic only allowed empty orders.

      // Delete order and free table
      await db.transaction((txn) async {
        await txn.delete('orders', where: 'id = ?', whereArgs: [id.toString()]);
        await txn.delete('order_items', where: 'order_id = ?', whereArgs: [id.toString()]);

        if (tableId != null) {
          final count = await txn.update(
            'tables',
            {'status': 0, 'active_order_id': null},
            where: 'id = ?',
            whereArgs: [tableId],
          );
          debugPrint('API [DELETE] /orders/$id/cancel: Table #$tableId detached. Affected: $count');
        }
      });

      WebSocketManager.instance.broadcast('tables_updated', {
        'table_id': ?tableId,
      });

      return Response.ok(jsonEncode({'status': 'success'}));
    });

    // Bill requested — client devices POST here to mark order as bill_requested
    router.post('/orders/<id>/bill_requested', (Request request, String id) async {
      try {
        final db = await DatabaseHelper.instance.database;
        await db.update(
          'orders',
          {
            'bill_requested': 1,
            'bill_requested_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        WebSocketManager.instance.broadcast('tables_updated', {});
        return Response.ok(jsonEncode({'ok': true}),
            headers: {'Content-Type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(
            body: jsonEncode({'error': e.toString()}));
      }
    });

  }
}
