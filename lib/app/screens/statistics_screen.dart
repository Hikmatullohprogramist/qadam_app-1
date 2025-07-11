import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qadam_app/app/services/coin_service.dart';
import '../services/statistics_service.dart';
import '../services/auth_service.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:qadam_app/app/components/loading_widget.dart';
import 'package:qadam_app/app/components/error_widget.dart';
import '../services/step_counter_service.dart';
import 'package:qadam_app/app/components/app_card.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({Key? key}) : super(key: key);

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    Future.microtask(() {
      final user = Provider.of<AuthService>(context, listen: false).user;
      if (user != null) {
        Provider.of<StatisticsService>(context, listen: false)
            .fetchWeeklyStats(user.uid);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statisticsService = Provider.of<StatisticsService>(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistika'),
        backgroundColor: Theme.of(context).primaryColor,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Kunlik'),
            Tab(text: 'Haftalik'),
            Tab(text: 'Oylik'),
          ],
          indicatorColor: Colors.white,
          labelColor: Colors.white,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Daily statistics (bugungi)
          _buildDailyTab(
              context,
              statisticsService.weeklyStats.isNotEmpty
                  ? statisticsService.weeklyStats.last
                  : null),
          // Weekly statistics
          _buildWeeklyTab(context, statisticsService),
          // Monthly statistics
          Center(
            child: Text(
              'Oylik statistika hali mavjud emas',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyTab(BuildContext context, DailyStats? todayStats) {
    if (todayStats == null) {
      // Fallback: StepCounterService'dan lokal qadamlarni ko'rsatish
      final stepService = Provider.of<StepCounterService>(context);
      final coinService = Provider.of<CoinService>(context);
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppCard(
              child: Column(
                children: [
                  Text('Bugungi natijalar',
                      style: Theme.of(context)
                          .textTheme
                          .displayMedium
                          ?.copyWith(fontSize: 18)),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem(context,
                          icon: Icons.directions_walk,
                          value: stepService.steps.toString(),
                          label: 'Qadam',
                          color: Theme.of(context).primaryColor),
                      _buildStatItem(context,
                          icon: Icons.monetization_on,
                          value: '+${coinService.todayEarned}',
                          label: 'Tanga',
                          color: const Color(0xFFFFC107)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                      'Bugungi statistik maʼlumotlar hali serverda mavjud emas, lekin lokal qadamlar ko‘rsatilmoqda.',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppCard(
            child: Column(
              children: [
                Text('Bugungi natijalar',
                    style: Theme.of(context)
                        .textTheme
                        .displayMedium
                        ?.copyWith(fontSize: 18)),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem(context,
                        icon: Icons.directions_walk,
                        value: todayStats.steps.toString(),
                        label: 'Qadam',
                        color: Theme.of(context).primaryColor),
                    _buildStatItem(context,
                        icon: Icons.monetization_on,
                        value: '+${todayStats.coins}',
                        label: 'Tanga',
                        color: const Color(0xFFFFC107)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyTab(
      BuildContext context, StatisticsService statisticsService) {
    if (statisticsService.isLoading) {
      return const LoadingWidget(message: 'Statistika yuklanmoqda...');
    }
    if (statisticsService.error != null) {
      return AppErrorWidget(
        message: statisticsService.error ?? 'Noma\'lum xatolik',
        onRetry: () => statisticsService.fetchWeeklyStats(
            Provider.of<AuthService>(context, listen: false).user?.uid ?? ''),
      );
    }
    if (statisticsService.weeklyStats.isEmpty) {
      return const Center(child: Text('Haftalik statistika mavjud emas.'));
    }
    final stats = statisticsService.weeklyStats;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.07),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          margin: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Haftalik Qadamlar Grafigi",
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 180,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: stats.isNotEmpty
                        ? (stats
                                .map((e) => e.steps)
                                .reduce((a, b) => a > b ? a : b)
                                .toDouble() *
                            1.2)
                        : 1000,
                    barTouchData: BarTouchData(
                      enabled: true,
                      touchTooltipData: BarTouchTooltipData(
                        // tooltipBgColor: Theme.of(context).primaryColor.withOpacity(0.9),
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          final stat = stats[group.x.toInt()];
                          return BarTooltipItem(
                            '${stat.day}\n',
                            const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            children: [
                              TextSpan(
                                text: 'Qadam: ${stat.steps}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.normal,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 36,
                          getTitlesWidget: (value, meta) {
                            if (value == 0) return const Text('0');
                            if (stats.isEmpty) return const SizedBox();
                            // Show only 2-3 labels for clarity
                            final max = stats
                                .map((e) => e.steps)
                                .reduce((a, b) => a > b ? a : b);
                            if (value == max * 1.2) {
                              return Text('${(max * 1.2).toInt()}');
                            }
                            if (value == (max / 2).roundToDouble()) {
                              return Text('${(max / 2).toInt()}');
                            }
                            return const SizedBox();
                          },
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (double value, TitleMeta meta) {
                            final idx = value.toInt();
                            if (idx < 0 || idx >= stats.length) {
                              return const SizedBox();
                            }
                            final day = stats[idx].day;
                            final label =
                                (day.length >= 2) ? day.substring(0, 2) : day;
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                label,
                                style: TextStyle(
                                  color: Theme.of(context).primaryColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          },
                          reservedSize: 32,
                        ),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    borderData: FlBorderData(
                      show: true,
                      border: Border(
                        left: BorderSide(
                          color: Theme.of(context).dividerColor,
                          width: 1,
                        ),
                        bottom: BorderSide(
                          color: Theme.of(context).dividerColor,
                          width: 1,
                        ),
                      ),
                    ),
                    barGroups: [
                      for (int i = 0; i < stats.length; i++)
                        BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: stats[i].steps.toDouble(),
                              color: i == stats.length - 1
                                  ? Colors.greenAccent.shade400
                                  : Theme.of(context).primaryColor,
                              width: 20,
                              borderRadius: BorderRadius.circular(8),
                              gradient: LinearGradient(
                                colors: [
                                  Theme.of(context)
                                      .primaryColor
                                      .withOpacity(0.8),
                                  Theme.of(context)
                                      .primaryColor
                                      .withOpacity(0.4),
                                ],
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                              ),
                              borderSide: BorderSide(
                                color: Colors.white.withOpacity(0.7),
                                width: 1.5,
                              ),
                            ),
                          ],
                        ),
                    ],
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (value) => FlLine(
                        color: Theme.of(context).dividerColor.withOpacity(0.2),
                        strokeWidth: 1,
                        dashArray: [4, 4],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: stats.length,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (context, index) {
            final stat = stats[index];
            return ListTile(
              leading: const Icon(Icons.calendar_today),
              title: Text(stat.day),
              subtitle: Text('Qadam: ${stat.steps} | Tanga: ${stat.coins}'),
            );
          },
        ),
      ],
    );
  }

  Widget _buildStatItem(BuildContext context,
      {required IconData icon,
      required String value,
      required String label,
      required Color color}) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 6),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 18, color: color)),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
