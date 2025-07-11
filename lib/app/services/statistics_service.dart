import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class DailyStats {
  final String day;
  final int steps;
  final int coins;
  DailyStats({required this.day, required this.steps, required this.coins});
}

class StatisticsService extends ChangeNotifier {
  List<DailyStats> _weeklyStats = [];
  bool _isLoading = false;
  String? _error;

  List<DailyStats> get weeklyStats => _weeklyStats;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> fetchWeeklyStats(String userId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('stats')
          .orderBy('date', descending: true)
          .limit(7)
          .get();
      _weeklyStats = snapshot.docs
          .map((doc) {
            final data = doc.data();
            int steps = 0;
            int coins = 0;
            // steps va coins ni int yoki string bo'lishidan qat'i nazar to'g'ri o'qish
            if (data['steps'] is int) {
              steps = data['steps'];
            } else if (data['steps'] is String) {
              steps = int.tryParse(data['steps']) ?? 0;
            }
            if (data['coins'] is int) {
              coins = data['coins'];
            } else if (data['coins'] is String) {
              coins = int.tryParse(data['coins']) ?? 0;
            }
            return DailyStats(
              day: data['day'].toString() ?? '',
              steps: steps,
              coins: coins,
            );
          })
          .toList()
          .reversed
          .toList();
      // Demo fallback olib tashlandi. Faqat Firestore ma'lumotlari ishlatiladi.
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
    }
  }
}
