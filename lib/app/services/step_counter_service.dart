import 'package:flutter/foundation.dart';
import 'package:pedometer/pedometer.dart';
import 'package:qadam_app/app/services/coin_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class StepCounterService extends ChangeNotifier {
  int _steps = 0;
  int _dailyGoal = 10000;
  DateTime? _lastResetDate;
  String _status = 'stopped';
  Stream<StepCount>? _stepCountStream;
  late SharedPreferences _prefs;
  late CoinService _coinService;

  StepCounterService() {
    _initPrefs();
  }

  int get steps => _steps;
  int get dailyGoal => _dailyGoal;
  String get status => _status;

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    _coinService = CoinService();
    _loadSteps();
    _loadGoal();
    _checkForDailyReset();
  }

  Future<void> _loadSteps() async {
    _steps = _prefs.getInt('steps') ?? 0;
    final lastResetString = _prefs.getString('lastResetDate');
    if (lastResetString != null) {
      _lastResetDate = DateTime.parse(lastResetString);
    }
    notifyListeners();
  }

  Future<void> _loadGoal() async {
    _dailyGoal = _prefs.getInt('dailyGoal') ?? 10000;
    notifyListeners();
  }

  Future<void> setDailyGoal(int goal) async {
    _dailyGoal = goal;
    await _prefs.setInt('dailyGoal', goal);
    notifyListeners();
  }

  Future<void> _saveSteps() async {
    await _prefs.setInt('steps', _steps);
    await _prefs.setString('lastResetDate', DateTime.now().toIso8601String());
  }

  Future<void> _checkForDailyReset() async {
    if (_lastResetDate == null) {
      _lastResetDate = DateTime.now();
      await _prefs.setString(
          'lastResetDate', _lastResetDate!.toIso8601String());
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
      // New day, reset steps
      _steps = 0;
      _lastResetDate = now;
      await _saveSteps();
      notifyListeners();
    }
  }

  void startCounting() {
    _setupPedometer();
    _status = 'counting';
    notifyListeners();
  }

  void stopCounting() {
    _status = 'stopped';
    notifyListeners();
  }

  void _setupPedometer() {
    _stepCountStream = Pedometer.stepCountStream;
    _stepCountStream?.listen(_onStepCount).onError(_onStepCountError);
  }

  void _onStepCount(StepCount event) async {
    _steps = event.steps;
    _saveSteps();
    syncStepsWithFirestore();
    await _updateAllChallengeProgress();
    await _coinService.addCoinsFromSteps(_steps);
    notifyListeners();
  }

  void _onStepCountError(error) {
    _status = 'error: $error';
    debugPrint('Step counter error: $error');
    notifyListeners();
  }

  // For testing or manual entry
  void addSteps(int count) async {
    _steps += count;
    _saveSteps();
    syncStepsWithFirestore();
    await _coinService.addCoinsFromSteps(_steps);

    notifyListeners();
  }

  void resetSteps() {
    _steps = 0;
    _saveSteps();
    notifyListeners();
  }

  // Sinxronizatsiya: lokal qadamlarni Firestore bilan bir xil qilish
  Future<void> syncStepsWithFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final userDoc =
        FirebaseFirestore.instance.collection('users').doc(user.uid);
    final statsDoc = userDoc
        .collection('stats')
        .doc(DateTime.now().toIso8601String().substring(0, 10));
    // Firestore'dan mavjud qadamlarni olish
    final snapshot = await statsDoc.get();
    int firestoreSteps = 0;
    if (snapshot.exists) {
      firestoreSteps = snapshot.data()?['steps'] ?? 0;
    }
    // Agar lokal qadamlar ko'proq bo'lsa, Firestore'ga yozamiz
    if (_steps > firestoreSteps) {
      await statsDoc.set({
        'day': DateTime.now().weekday,
        'steps': _steps,
        'coins': 0, // coins logikasi CoinService'da
        'date': DateTime.now(),
      }, SetOptions(merge: true));
    } else if (firestoreSteps > _steps) {
      // Agar Firestore ko'proq bo'lsa, lokalga yozamiz
      _steps = firestoreSteps;
      await _saveSteps();
      notifyListeners();
    }
  }

  Future<void> _updateAllChallengeProgress() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final userChallenges = await FirebaseFirestore.instance
        .collection('user_challenges')
        .where('userId', isEqualTo: user.uid)
        .get();
    for (var doc in userChallenges.docs) {
      final data = doc.data();
      final challengeId = data['challengeId'];
      final targetSteps = await _getChallengeTargetSteps(challengeId);
      if (targetSteps > 0) {
        final progress = (_steps / targetSteps).clamp(0.0, 1.0);
        await FirebaseFirestore.instance
            .collection('user_challenges')
            .doc('${user.uid}_$challengeId')
            .update({'progress': progress, 'isCompleted': progress >= 1.0});
      }
    }
  }

  Future<int> _getChallengeTargetSteps(String challengeId) async {
    final doc = await FirebaseFirestore.instance
        .collection('challenges')
        .doc(challengeId)
        .get();
    if (doc.exists) {
      return doc.data()?['targetSteps'] ?? 0;
    }
    return 0;
  }
}
