import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qadam_app/app/models/achievement_model.dart';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CoinService extends ChangeNotifier {
  int _coins = 0;
  int _todayEarned = 0;
  int _stepsPerCoin =
      10; // Number of steps needed for 1 coin (1000 qadam = 100 tanga uchun 10)
  int _dailyCoinLimit = 100; // Maximum coins per day
  DateTime? _lastResetDate;
  DateTime? _lastLoginDate;
  int? _lastBonusAmount;
  DateTime? _lastBonusDate;
  late SharedPreferences _prefs;
  bool _showBonusSnackbar = false;
  final List<AchievementModel> _achievements = [];

  CoinService() {
    _initPrefs();
  }

  int get coins => _coins;
  int get todayEarned => _todayEarned;
  int get stepsPerCoin => _stepsPerCoin;
  int get dailyCoinLimit => _dailyCoinLimit;
  int? get lastBonusAmount => _lastBonusAmount;
  DateTime? get lastBonusDate => _lastBonusDate;
  bool get showBonusSnackbar => _showBonusSnackbar;
  List<AchievementModel> get achievements => _achievements;

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadCoins();
    await _loadAchievements();
    await _checkForDailyReset();
    await _checkDailyLoginBonus();
    // stepsPerCoin ni prefs'dan o'qish
    _stepsPerCoin = _prefs.getInt('stepsPerCoin') ?? 10;
    // dailyCoinLimit ni prefs'dan o'qish (agar kerak bo'lsa, default 100)
    _dailyCoinLimit = _prefs.getInt('dailyCoinLimit') ?? 100;
  }

  Future<void> _loadCoins() async {
    _coins = _prefs.getInt('coins') ?? 0;
    _todayEarned = _prefs.getInt('todayEarned') ?? 0;
    final lastResetString = _prefs.getString('coinLastResetDate');
    if (lastResetString != null) {
      _lastResetDate = DateTime.parse(lastResetString);
    }
    notifyListeners();
  }

  Future<void> _loadAchievements() async {
    final achievementsString = _prefs.getString('achievements');
    if (achievementsString != null) {
      final List decoded = jsonDecode(achievementsString);
      _achievements.clear();
      _achievements
          .addAll(decoded.map((e) => AchievementModel.fromMap(e)).toList());
    }
    notifyListeners();
  }

  Future<void> _saveCoins() async {
    await _prefs.setInt('coins', _coins);
    await _prefs.setInt('todayEarned', _todayEarned);
    await _prefs.setString(
        'coinLastResetDate', DateTime.now().toIso8601String());
  }

  Future<void> _saveAchievements() async {
    final encoded = jsonEncode(_achievements.map((e) => e.toMap()).toList());
    await _prefs.setString('achievements', encoded);
  }

  Future<void> _checkForDailyReset() async {
    if (_lastResetDate == null) {
      _lastResetDate = DateTime.now();
      await _prefs.setString(
          'coinLastResetDate', _lastResetDate!.toIso8601String());
      return;
    }

    final now = DateTime.now();
    final lastMidnight = DateTime(now.year, now.month, now.day);
    final resetMidnight = DateTime(
      _lastResetDate!.year,
      _lastResetDate!.month,
      _lastResetDate!.day,
    );

    if (lastMidnight.isAfter(resetMidnight)) {
      // New day, reset today's earned coins
      _todayEarned = 0;
      _lastResetDate = now;
      await _saveCoins();
      notifyListeners();
    }
  }

  Future<void> _checkDailyLoginBonus() async {
    final now = DateTime.now();
    final lastLoginString = _prefs.getString('lastLoginDate');
    if (lastLoginString != null) {
      _lastLoginDate = DateTime.parse(lastLoginString);
    }
    if (_lastLoginDate == null ||
        now.year != _lastLoginDate!.year ||
        now.month != _lastLoginDate!.month ||
        now.day != _lastLoginDate!.day) {
      int bonus;
      if (now.difference(_lastLoginDate ?? now).inDays >= 7) {
        bonus = 20;
      } else {
        bonus = 10;
      }
      _coins += bonus;
      _lastBonusAmount = bonus;
      _lastBonusDate = now;
      _showBonusSnackbar = true;
      await _prefs.setInt('coins', _coins);
      await _prefs.setString('lastLoginDate', now.toIso8601String());
      _lastLoginDate = now;
      notifyListeners();
    }
  }

  int _getWeekNumber(DateTime date) {
    final firstDayOfYear = DateTime(date.year, 1, 1);
    final daysOffset = firstDayOfYear.weekday - 1;
    final firstMonday = firstDayOfYear.subtract(Duration(days: daysOffset));
    return ((date.difference(firstMonday).inDays) / 7).ceil();
  }

  // Add coins based on steps - called when steps are updated
  Future<int> addCoinsFromSteps(int steps) async {
    if (_todayEarned >= _dailyCoinLimit) {
      print('Daily limit reached');

      return 0; // Daily limit reached
    }

    int earnedCoins = (steps / _stepsPerCoin).floor();

    print('Steps: $steps');
    print('Earned coins: $earnedCoins');
    print('Today earned: $_todayEarned');
    print('Daily limit: $_dailyCoinLimit');

    // Cap to daily limit
    if (_todayEarned + earnedCoins > _dailyCoinLimit) {
      earnedCoins = _dailyCoinLimit - _todayEarned;
    }

    if (earnedCoins > 0) {
      _coins += earnedCoins;
      _todayEarned += earnedCoins;
      await _saveCoins();
      notifyListeners();
    }

    return earnedCoins;
  }

  // Add coins from challenge or referral
  Future<void> addCoins(int amount) async {
    _coins += amount;
    await _saveCoins();
    await _saveStatsToFirestore();
    notifyListeners();
  }

  Future<void> _saveStatsToFirestore({int? currentSteps}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final userDoc =
        FirebaseFirestore.instance.collection('users').doc(user.uid);
    final statsDoc = userDoc
        .collection('stats')
        .doc(DateTime.now().toIso8601String().substring(0, 10));
    int steps = 0;
    if (currentSteps != null) {
      steps = currentSteps;
    } else {
      try {
        // Try to get steps from Firestore if available
        final snapshot = await statsDoc.get();
        if (snapshot.exists) {
          steps = snapshot.data()?['steps'] ?? 0;
        }
      } catch (_) {}
    }
    await statsDoc.set({
      'day': DateTime.now().toString().substring(0, 10), // Masalan: 2025-07-09
      'steps': steps, // Qadamlar soni
      'coins': _todayEarned, // Shu kunda topilgan tanga
      'date': DateTime.now(), // To‘liq vaqt (timestamp)
    }, SetOptions(merge: true));
  }

  // Use coins for purchase
  Future<bool> useCoins(int amount) async {
    if (_coins < amount) {
      return false; // Not enough coins
    }

    _coins -= amount;
    await _saveCoins();
    notifyListeners();
    return true;
  }

  // For withdrawal to cash
  Future<bool> withdrawCoins(int amount) async {
    // Minimal cheklov olib tashlandi
    if (_coins < amount) {
      return false; // Not enough coins
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    // Firestore'ga so'rov yozish
    await FirebaseFirestore.instance.collection('withdraw_requests').add({
      'userId': user.uid,
      'amount': amount,
      'date': DateTime.now(),
      'status': 'pending',
    });

    // Tangani balansdan ayirish (so'rov yuborilganda darhol ayirilyapti)
    _coins -= amount;
    await _saveCoins();
    notifyListeners();
    return true;
  }

  // For adding referral bonus
  Future<void> addReferralBonus(String referrerId, String referredId) async {
    // Referrer (taklif qilgan) uchun
    await FirebaseFirestore.instance
        .collection('users')
        .doc(referrerId)
        .update({'coins': FieldValue.increment(200)});
    // Referred (kirgan) uchun
    await FirebaseFirestore.instance
        .collection('users')
        .doc(referredId)
        .update({'coins': FieldValue.increment(50)});
  }

  // Set steps per coin ratio
  Future<void> setStepsPerCoin(int steps) async {
    _stepsPerCoin = steps;
    await _prefs.setInt('stepsPerCoin', steps);
    notifyListeners();
  }

  // Set daily coin limit
  Future<void> setDailyCoinLimit(int limit) async {
    _dailyCoinLimit = limit;
    await _prefs.setInt('dailyCoinLimit', limit);
    notifyListeners();
  }

  void clearBonusSnackbar() {
    _showBonusSnackbar = false;
    notifyListeners();
  }

  void addChallengeAchievement(String challengeTitle, int reward) {
    // Check if achievement already exists for this challenge and reward
    final alreadyExists = _achievements
        .any((a) => a.challengeTitle == challengeTitle && a.reward == reward);
    if (alreadyExists) return;
    _achievements.add(AchievementModel(
      challengeTitle: challengeTitle,
      reward: reward,
      date: DateTime.now(),
    ));
    _saveAchievements();
    notifyListeners();
  }

  // Persist local challenge claim state
  Future<void> saveLocalChallengeState(List challenges) async {
    final localStates = _prefs.getString('localChallengeStates');
    Map<String, dynamic> stateMap = {};
    if (localStates != null) {
      stateMap = jsonDecode(localStates);
    }
    for (var c in challenges) {
      if (c.id.startsWith('daily_') ||
          c.id.startsWith('profile_') ||
          c.id.startsWith('invite_') ||
          c.id.startsWith('weekly_') ||
          c.id == 'share_stats') {
        stateMap[c.id] = {
          'rewardClaimed': c.rewardClaimed ?? false,
          'isCompleted': c.isCompleted,
        };
      }
    }
    await _prefs.setString('localChallengeStates', jsonEncode(stateMap));
  }

  Future<void> loadLocalChallengeState(List challenges) async {
    final localStates = _prefs.getString('localChallengeStates');
    if (localStates != null) {
      final stateMap = jsonDecode(localStates);
      for (var c in challenges) {
        if (stateMap[c.id] != null) {
          c.rewardClaimed = stateMap[c.id]['rewardClaimed'] ?? false;
          c.isCompleted = stateMap[c.id]['isCompleted'] ?? false;
        }
      }
    }
  }

  int getDailyStreakReward(int week) {
    if (week == 1) return 10;
    if (week == 2) return 20;
    if (week == 3) return 30;
    if (week >= 4) return 40;
    return 10;
  }
}
