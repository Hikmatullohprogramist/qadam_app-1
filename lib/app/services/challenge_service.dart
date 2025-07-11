import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:qadam_app/app/models/challenge_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qadam_app/app/services/coin_service.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/foundation.dart';

class ChallengeService extends ChangeNotifier {
  List<ChallengeModel> _challenges = [];
  bool _isLoading = false;
  String? _error;
  CoinService? _coinService;
  bool _isLoaded = false;

  List<ChallengeModel> get challenges => _challenges;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<ChallengeModel> get defaultChallenges => [
        ChallengeModel(
          id: 'daily_steps',
          title: 'Kunlik 5000 qadam',
          description: 'Bugun 5000 qadam yuring va 50 tanga yutib oling!',
          reward: 50,
          targetSteps: 5000,
          duration: 1,
          type: 'daily',
        ),
        ChallengeModel(
          id: 'invite_friend',
          title: 'Do\'st taklif qil',
          description: 'Do\'stingizni ilovaga taklif qiling va 20 tanga oling!',
          reward: 20,
          targetSteps: 0,
          duration: 1,
          type: 'referral',
        ),
        ChallengeModel(
          id: 'profile_pic',
          title: 'Profil rasm qo\'yish',
          description: 'Profil rasmini o\'rnatganingiz uchun 10 tanga!',
          reward: 10,
          targetSteps: 0,
          duration: 1,
          type: 'profile',
        ),
        ChallengeModel(
          id: 'weekly_steps',
          title: 'Haftada 7 kun yur',
          description: 'Haftada har kuni yurib, 100 tanga yutib oling!',
          reward: 100,
          targetSteps: 35000,
          duration: 7,
          type: 'weekly',
        ),
        ChallengeModel(
          id: 'share_stats',
          title: 'Statistikani do\'st bilan bo\'lish',
          description:
              'Statistikangizni do\'stingiz bilan bo\'lishing va 15 tanga oling!',
          reward: 15,
          targetSteps: 0,
          duration: 1,
          type: 'social',
        ),
        ChallengeModel(
          id: 'daily_10000_steps',
          title: 'Bir kunda 10 000 qadam yur',
          description: 'Bir kunda 10 000 qadam yurib, 100 tanga yutib oling!',
          reward: 100,
          targetSteps: 10000,
          duration: 1,
          type: 'daily',
        ),
      ];

  List<ChallengeModel> filterValidChallenges(List<ChallengeModel> challenges) {
    return challenges
        .where((c) =>
            c.title.isNotEmpty &&
            c.title != '21211212' &&
            c.title != 'TITLEE' &&
            c.title.toLowerCase() != 'test' &&
            c.title.toLowerCase() != 'muhammadsodiq' &&
            c.title.length > 3)
        .toList();
  }

  // Foydalanuvchi uchun challenge progressini olish
  Future<double> getUserChallengeProgress(String challengeId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 0.0;
    final doc = await FirebaseFirestore.instance
        .collection('user_challenges')
        .doc('${user.uid}_$challengeId')
        .get();
    if (doc.exists) {
      return (doc.data()?['progress'] ?? 0.0) * 1.0;
    }
    return 0.0;
  }

  Future<void> joinChallenge(String challengeId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('user_challenges')
          .doc('${user.uid}_$challengeId')
          .set({
        'userId': user.uid,
        'challengeId': challengeId,
        'progress': 0.0,
        'isCompleted': false,
        'rewardClaimed': false,
      });

      notifyListeners();
    } catch (e, stack) {
      debugPrint('Xatolik: $e');
      debugPrint('Stacktrace: $stack');
    }
  }

  // Progressni yangilash
  Future<void> updateUserChallengeProgress(
      String challengeId, double progress) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance
        .collection('user_challenges')
        .doc('${user.uid}_$challengeId')
        .update({'progress': progress});
    notifyListeners();
  }

  // Challenge tugagach, mukofotni olish
  Future<void> claimChallengeReward(String challengeId, int reward) async {
    // If this is a local (default) challenge, do not write to Firestore
    if (challengeId.startsWith('daily_') ||
        challengeId.startsWith('profile_') ||
        challengeId.startsWith('invite_') ||
        challengeId.startsWith('weekly_') ||
        challengeId == 'share_stats') {
      // Prevent duplicate claim
      final index = _challenges.indexWhere((c) => c.id == challengeId);
      if (index != -1) {
        if (_challenges[index].rewardClaimed == true) return;
        _challenges[index] =
            _challenges[index].copyWith(isCompleted: true, rewardClaimed: true);
        notifyListeners();
        // Save local challenge state
        if (_coinService != null) {
          await _coinService!.saveLocalChallengeState(_challenges);
        }
      }
      notifyListeners();
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance
        .collection('user_challenges')
        .doc('${user.uid}_$challengeId')
        .update({'rewardClaimed': true, 'isCompleted': true});
    // Mukofotni user balansiga qo'shish (user document)
    final userRef =
        FirebaseFirestore.instance.collection('users').doc(user.uid);
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final userDoc = await transaction.get(userRef);
      final currentBalance = userDoc.data()?['coins'] ?? 0;
      transaction.update(userRef, {
        'coins': currentBalance + reward,
      });
    });
    notifyListeners();
  }

  Future<void> fetchChallenges({bool force = false}) async {
    if (_isLoaded && !force)
      return; // allaqachon yuklangan bo‘lsa, qayta yuklamaydi
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final challengesRef =
          FirebaseFirestore.instance.collection('user_challenges');
      final snapshot = await challengesRef.get();

      _challenges.clear();
      final user = FirebaseAuth.instance.currentUser;
      if (snapshot.docs.isEmpty) {
        _challenges.addAll(filterValidChallenges(defaultChallenges));
      } else {
        List<ChallengeModel> firestoreChallenges = [];
        for (var doc in snapshot.docs) {
          final data = doc.data();
          bool rewardClaimed = false;
          bool isCompleted = false;
          if (user != null) {
            final userChallengeDoc = await FirebaseFirestore.instance
                .collection('user_challenges')
                .doc('${user.uid}_${doc.id}')
                .get();
            if (userChallengeDoc.exists) {
              rewardClaimed =
                  userChallengeDoc.data()?['rewardClaimed'] ?? false;
              isCompleted = userChallengeDoc.data()?['isCompleted'] ?? false;
            }
          }
          firestoreChallenges.add(ChallengeModel(
            id: doc.id,
            title: data['title']?.toString() ?? '',
            description: data['description']?.toString() ?? '',
            reward: int.tryParse(data['reward']?.toString() ?? '0') ?? 0,
            targetSteps:
                int.tryParse(data['targetSteps']?.toString() ?? '0') ?? 0,
            duration: int.tryParse(data['duration']?.toString() ?? '1') ?? 1,
            type: data['type']?.toString() ?? 'daily',
            startDate: data['startDate'] != null
                ? DateTime.tryParse(data['startDate'].toString()) ??
                    DateTime.now()
                : DateTime.now(),
            endDate: data['endDate'] != null
                ? DateTime.tryParse(data['endDate'].toString()) ??
                    DateTime.now()
                : DateTime.now(),
            isCompleted: isCompleted,
            rewardClaimed: rewardClaimed,
            progress: (data['progress'] is num)
                ? (data['progress'] as num).toDouble()
                : double.tryParse(data['progress']?.toString() ?? '0.0') ?? 0.0,
          ));
        }
        _challenges.addAll(firestoreChallenges);
      }

      // Load local challenge state after fetching
      if (_coinService != null) {
        await _coinService!.loadLocalChallengeState(_challenges);
      }

      // Demo challenge-lar olib tashlandi. Faqat Firestore ma'lumotlari ishlatiladi.

      // Demo challenge-larni progress bilan har doim ko'rsatish
      for (int i = 0; i < _challenges.length; i++) {
        final c = _challenges[i];
        if (c.progress == null || c.progress < 1.0) {
          // Demo uchun progressni random yoki 0.5 qilib qo'yamiz
          _challenges[i] = c.copyWith(progress: 0.5);
        }
      }

      debugPrint(_challenges.length.toString());

      _isLoading = false;
      _isLoaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint(e.toString());
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> updateChallengeProgress(
      String challengeId, double progress) async {
    try {
      final isCompleted = progress >= 1.0;
      await FirebaseFirestore.instance
          .collection('challenges')
          .doc(challengeId)
          .update({'progress': progress, 'isCompleted': isCompleted});

      final index = _challenges.indexWhere((c) => c.id == challengeId);
      if (index != -1) {
        _challenges[index] = _challenges[index]
            .copyWith(progress: progress, isCompleted: isCompleted);
        notifyListeners();
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> completeChallenge(String challengeId) async {
    try {
      // Get the challenge reward amount before marking as complete
      final challenge = _challenges.firstWhere((c) => c.id == challengeId);
      final rewardAmount = challenge.reward;

      await FirebaseFirestore.instance
          .collection('challenges')
          .doc(challengeId)
          .update({
        'isCompleted': true,
        'completedAt': DateTime.now(),
      });

      // Update user's balance in Firestore
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userRef =
            FirebaseFirestore.instance.collection('users').doc(user.uid);

        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final userDoc = await transaction.get(userRef);
          final currentBalance = userDoc.data()?['balance'] ?? 0;
          transaction.update(userRef, {
            'balance': currentBalance + rewardAmount,
          });
        });
      }

      final index = _challenges.indexWhere((c) => c.id == challengeId);
      if (index != -1) {
        _challenges[index] = _challenges[index].copyWith(isCompleted: true);
        notifyListeners();
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  // Challenge qo'shish
  Future<void> addChallenge(ChallengeModel challenge) async {
    try {
      final docRef =
          await FirebaseFirestore.instance.collection('challenges').add({
        'title': challenge.title,
        'description': challenge.description,
        'reward': challenge.reward,
        'targetSteps': challenge.targetSteps,
        'duration': challenge.duration,
        'type': challenge.type,
        'startDate': challenge.startDate,
        'endDate': challenge.endDate,
        'progress': challenge.progress,
        'isCompleted': challenge.isCompleted,
      });

      final newChallenge = ChallengeModel(
        id: docRef.id,
        title: challenge.title,
        description: challenge.description,
        reward: challenge.reward,
        targetSteps: challenge.targetSteps,
        duration: challenge.duration,
        type: challenge.type,
        startDate: challenge.startDate,
        endDate: challenge.endDate,
        progress: challenge.progress,
        isCompleted: challenge.isCompleted,
        rewardClaimed: challenge.rewardClaimed,
      );

      _challenges.add(newChallenge);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> deleteChallenge(String challengeId) async {
    try {
      await FirebaseFirestore.instance
          .collection('challenges')
          .doc(challengeId)
          .delete();

      _challenges.removeWhere((c) => c.id == challengeId);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  // Do'stni challenge'ga taklif qilish va push notification yuborish
  Future<void> inviteFriendToChallenge({
    required String challengeId,
    required String friendEmail,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    // 1. Firestore'ga taklif yozuvi
    await FirebaseFirestore.instance.collection('challenge_invites').add({
      'challengeId': challengeId,
      'inviterId': user.uid,
      'inviterEmail': user.email,
      'friendEmail': friendEmail,
      'status': 'pending',
      'sentAt': DateTime.now(),
    });
    // 2. Agar do'st FCM tokeni bo'lsa, push notification yuborish (bu joyda backend yoki cloud function kerak)
    // TODO: Cloud Function orqali friendEmail bo'yicha FCM token topib, push notification yuborish
  }

  // Do'st taklifini qabul qilganda, unga ham user_challenges hujjati yaratiladi
  Future<void> acceptChallengeInvite({
    required String challengeId,
    required String userId,
  }) async {
    await FirebaseFirestore.instance
        .collection('user_challenges')
        .doc('${userId}_$challengeId')
        .set({
      'userId': userId,
      'challengeId': challengeId,
      'progress': 0.0,
      'isCompleted': false,
      'rewardClaimed': false,
    });
    // TODO: Push notification yuborish (ikkala userga bonus va xabar)
  }

  // Offline progress uchun lokalda saqlash va sinxronizatsiya
  Future<void> syncChallengeProgressWithFirestore(String challengeId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final prefs = await SharedPreferences.getInstance();
    final localKey = 'challenge_progress_${user.uid}_$challengeId';
    final doc = await FirebaseFirestore.instance
        .collection('user_challenges')
        .doc('${user.uid}_$challengeId')
        .get();
    double firestoreProgress = 0.0;
    if (doc.exists) {
      firestoreProgress = (doc.data()?['progress'] ?? 0.0) * 1.0;
    }
    double localProgress = prefs.getDouble(localKey) ?? 0.0;
    // Eng katta progressni har ikki joyga yozamiz
    final maxProgress =
        firestoreProgress > localProgress ? firestoreProgress : localProgress;
    await prefs.setDouble(localKey, maxProgress);
    await FirebaseFirestore.instance
        .collection('user_challenges')
        .doc('${user.uid}_$challengeId')
        .set({'progress': maxProgress}, SetOptions(merge: true));
    notifyListeners();
  }

  // Lokal progressni yangilash
  Future<void> saveLocalChallengeProgress(
      String challengeId, double progress) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final prefs = await SharedPreferences.getInstance();
    final localKey = 'challenge_progress_${user.uid}_$challengeId';
    await prefs.setDouble(localKey, progress);
  }

  void setCoinService(CoinService coinService) {
    _coinService = coinService;
  }

  void addTestSteps(int steps) {
    // Implementation of addTestSteps method
  }

  Future<void> leaveChallenge(String challengeId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance
        .collection('user_challenges')
        .doc('${user.uid}_$challengeId')
        .delete();
    notifyListeners();
  }
}

class MyBannerAdWidget extends StatefulWidget {
  const MyBannerAdWidget({Key? key}) : super(key: key);

  @override
  State<MyBannerAdWidget> createState() => _MyBannerAdWidgetState();
}

class _MyBannerAdWidgetState extends State<MyBannerAdWidget> {
  BannerAd? _bannerAd;

  @override
  void initState() {
    super.initState();
    _bannerAd = BannerAd(
      adUnitId:
          'ca-app-pub-7180097986291909/1830667352', // Sizning Banner Ad Unit ID
      size: AdSize.banner,
      request: AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) => setState(() {}),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_bannerAd == null) {
      return SizedBox.shrink();
    }
    return Container(
      alignment: Alignment.center,
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }
}
