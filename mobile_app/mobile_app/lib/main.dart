import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math' as math;

enum TimeRange { hour, day, week, all }

void main() => runApp(SensorApp());

class SensorApp extends StatefulWidget {
  @override
  State<SensorApp> createState() => _SensorAppState();
}

class _SensorAppState extends State<SensorApp> {
  bool darkMode = false;
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sensor Monitor',
      theme: darkMode
          ? ThemeData.dark().copyWith(
              scaffoldBackgroundColor: Colors.grey[900],
              colorScheme: ColorScheme.dark(primary: Colors.teal),
            )
          : ThemeData(
              primarySwatch: Colors.teal,
              visualDensity: VisualDensity.adaptivePlatformDensity,
              scaffoldBackgroundColor: Colors.grey[100],
            ),
      home: SensorDashboard(
        onToggleTheme: () => setState(() => darkMode = !darkMode),
        darkMode: darkMode,
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}

class SensorDashboard extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final bool darkMode;
  SensorDashboard({required this.onToggleTheme, required this.darkMode});
  @override
  _SensorDashboardState createState() => _SensorDashboardState();
}

class _SensorDashboardState extends State<SensorDashboard> with SingleTickerProviderStateMixin {
  List<double> temps = [], hums = [];
  List<String> times = [];
  List<bool> relayStates = [];
  double? latestTemp, latestHum;
  bool? latestRelayState;
  double tempThreshold = 26.0;
  double humThreshold = 70.0;
  double? fetchedTempThreshold, fetchedHumThreshold;
  final tempController = TextEditingController();
  final humController = TextEditingController();
  Timer? _timer;
  bool isRefreshing = false;
  TimeRange selectedRange = TimeRange.day;

  final String apiUrl = 'http://192.168.1.6:5000/api/data';

  @override
  void initState() {
    super.initState();
    fetchData();
    fetchThresholds();
    _timer = Timer.periodic(Duration(seconds: 10), (timer) {
      fetchData();
      fetchThresholds();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    tempController.dispose();
    humController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> filterByTimeRange(List<Map<String, dynamic>> data) {
    if (selectedRange == TimeRange.all) return data;
    final now = DateTime.now();
    Duration range;
    switch (selectedRange) {
      case TimeRange.hour:
        range = Duration(hours: 1);
        break;
      case TimeRange.day:
        range = Duration(days: 1);
        break;
      case TimeRange.week:
        range = Duration(days: 7);
        break;
      default:
        range = Duration(days: 365);
    }
    return data.where((d) {
      final t = d['timestamp'];
      DateTime? dt;
      try {
        dt = DateTime.tryParse(t);
      } catch (_) {}
      if (dt == null) return true;
      return now.difference(dt) <= range;
    }).toList();
  }

  Future<void> fetchData() async {
    if (isRefreshing) return;
    setState(() => isRefreshing = true);
    try {
      final res = await http.get(Uri.parse(apiUrl));
      if (res.statusCode == 200) {
        var data = jsonDecode(res.body);
        print('API response: ' + data.toString());
        // Deduplicate by timestamp
        var uniqueData = <Map<String, dynamic>>[];
        var seenTimestamps = <String>{};
        for (var item in data) {
          String timestamp = item['timestamp'];
          if (!seenTimestamps.contains(timestamp)) {
            seenTimestamps.add(timestamp);
            uniqueData.add(item);
          }
        }
        // Filter by selected time range
        uniqueData = filterByTimeRange(uniqueData);
        relayStates = List<bool>.from(uniqueData.map((d) => d['relay'] == 1));
        print('Parsed relay states: ' + relayStates.toString());
        print('Timestamps: ' + uniqueData.map((d) => d['timestamp']).toList().toString());
        setState(() {
          temps = List<double>.from(uniqueData.map((d) => d['temperature']));
          hums = List<double>.from(uniqueData.map((d) => d['humidity']));
          times = List<String>.from(uniqueData.map((d) => d['timestamp']));
          latestTemp = temps.isNotEmpty ? temps.last : null;
          latestHum = hums.isNotEmpty ? hums.last : null;
          latestRelayState = relayStates.isNotEmpty ? relayStates.first : null;
          print('latestRelayState: ' + latestRelayState.toString());
        });
      }
    } catch (e) {
      print("Error: $e");
    } finally {
      setState(() => isRefreshing = false);
    }
  }

  Future<void> fetchThresholds() async {
    try {
      final res = await http.get(Uri.parse(apiUrl.replaceAll('/data', '/thresholds')));
      if (res.statusCode == 200) {
        var data = jsonDecode(res.body);
        setState(() {
          fetchedTempThreshold = data['temperature']?.toDouble();
          fetchedHumThreshold = data['humidity']?.toDouble();
          tempController.text = fetchedTempThreshold?.toStringAsFixed(1) ?? '26.0';
          humController.text = fetchedHumThreshold?.toStringAsFixed(1) ?? '70.0';
        });
      }
    } catch (e) {
      print("Error fetching thresholds: $e");
    }
  }

  Future<void> updateThresholds() async {
    double? newTemp = double.tryParse(tempController.text);
    double? newHum = double.tryParse(humController.text);
    if (newTemp == null || newHum == null) return;

    final url = apiUrl.replaceAll('/data', '/thresholds');
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'temperature': newTemp, 'humidity': newHum}),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Thresholds updated")));
        fetchThresholds();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Update failed")));
      }
    } catch (e) {
      print("Threshold update error: $e");
    }
  }

  Widget buildReadingCard(String title, double? value, IconData icon, Color color) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withOpacity(0.7), color],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 15,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, size: 24, color: Colors.white),
                    ),
                    SizedBox(width: 12),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                Text(
                  title == "Temperature" ? "°C" : "%",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Text(
              value != null ? "${value.toStringAsFixed(1)}" : "Loading...",
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            if (temps.isNotEmpty && hums.isNotEmpty) ...[
              SizedBox(height: 8),
              Text(
                "Avg: ${title == "Temperature" ? (temps.reduce((a, b) => a + b) / temps.length).toStringAsFixed(1) : (hums.reduce((a, b) => a + b) / hums.length).toStringAsFixed(1)}",
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white.withOpacity(0.8),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget buildRelayStatus() {
    bool overTemp = latestTemp != null && latestTemp! > (fetchedTempThreshold ?? tempThreshold);
    bool overHum = latestHum != null && latestHum! > (fetchedHumThreshold ?? humThreshold);
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.grey[100]!,
            Colors.grey[50]!,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Relay Status',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: latestRelayState == true ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: latestRelayState == true ? Colors.green : Colors.red,
                      ),
                    ),
                    SizedBox(width: 6),
                    Text(
                      latestRelayState == true ? 'Active' : 'Inactive',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: latestRelayState == true ? Colors.green : Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (overTemp || overHum)
            Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning, color: Colors.orange, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      overTemp && overHum
                          ? 'Temperature & Humidity over threshold!'
                          : overTemp
                              ? 'Temperature over threshold!'
                              : 'Humidity over threshold!',
                      style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                      softWrap: true,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget buildThresholdConfig() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.grey[100]!,
            Colors.grey[50]!,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Configure Thresholds",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: tempController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Temp Threshold (°C)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: humController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Humidity Threshold (%)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: Icon(Icons.save),
              label: Text("Save Thresholds"),
              onPressed: updateThresholds,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.teal,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildAnimatedCard({required Widget child, required int index}) {
    return AnimatedContainer(
      duration: Duration(milliseconds: 400 + index * 100),
      curve: Curves.easeOutBack,
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: child,
    );
  }

  Widget buildStatsRow(List<double> values, Color color) {
    if (values.isEmpty) return SizedBox();
    final min = values.reduce(math.min);
    final max = values.reduce(math.max);
    final avg = values.reduce((a, b) => a + b) / values.length;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _statBox('Min', min, color),
        _statBox('Avg', avg, color),
        _statBox('Max', max, color),
      ],
    );
  }

  Widget _statBox(String label, double value, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
          SizedBox(height: 4),
          Text(value.toStringAsFixed(1), style: TextStyle(fontSize: 16, color: color)),
        ],
      ),
    );
  }

  Widget buildTimeRangeSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _timeRangeChip('1H', TimeRange.hour),
          _timeRangeChip('1D', TimeRange.day),
          _timeRangeChip('1W', TimeRange.week),
          _timeRangeChip('All', TimeRange.all),
        ],
      ),
    );
  }

  Widget _timeRangeChip(String label, TimeRange range) {
    final selected = selectedRange == range;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() {
        selectedRange = range;
        fetchData();
      }),
      selectedColor: Colors.teal,
      labelStyle: TextStyle(color: selected ? Colors.white : Colors.teal),
      backgroundColor: Colors.teal.withOpacity(0.1),
    );
  }

  Widget buildGraph(String label, List<double> values, Color color) {
    if (values.isEmpty) return SizedBox();
    final minY = values.reduce(math.min);
    final maxY = values.reduce(math.max);
    final yRange = maxY == minY ? 2.0 : (maxY - minY) * 1.2;
    final yMin = minY - (yRange * 0.15);
    final yMax = maxY + (yRange * 0.15);
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.grey[100]!,
            Colors.grey[50]!,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey[800])),
            ],
          ),
          SizedBox(height: 8),
          buildStatsRow(values, color),
          SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  horizontalInterval: yRange / 4,
                  verticalInterval: math.max(values.length / 4, 1),
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: Colors.grey.withOpacity(0.2),
                      strokeWidth: 1,
                    );
                  },
                  getDrawingVerticalLine: (value) {
                    return FlLine(
                      color: Colors.grey.withOpacity(0.2),
                      strokeWidth: 1,
                    );
                  },
                ),
                titlesData: FlTitlesData(
                  show: true,
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: math.max(values.length / 4, 1),
                      getTitlesWidget: (value, meta) {
                        if (value.toInt() >= 0 && value.toInt() < times.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              times[value.toInt()],
                              style: TextStyle(color: Colors.grey[600], fontSize: 12),
                            ),
                          );
                        }
                        return Text('');
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: yRange / 4,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toStringAsFixed(1),
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        );
                      },
                      reservedSize: 42,
                    ),
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(color: Colors.grey.withOpacity(0.2)),
                ),
                minX: 0,
                maxX: math.max(values.length - 1.0, 1),
                minY: yMin,
                maxY: yMax,
                lineBarsData: [
                  LineChartBarData(
                    spots: values.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
                    isCurved: true,
                    color: color,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) {
                        return FlDotCirclePainter(
                          radius: 4,
                          color: color,
                          strokeWidth: 2,
                          strokeColor: Colors.white,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: color.withOpacity(0.1),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [color.withOpacity(0.2), color.withOpacity(0.0)],
                      ),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    tooltipBgColor: Colors.grey[800]!.withOpacity(0.8),
                    getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
                      return touchedBarSpots.map((barSpot) {
                        return LineTooltipItem(
                          '${barSpot.y.toStringAsFixed(1)}',
                          TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        );
                      }).toList();
                    },
                  ),
                  handleBuiltInTouches: true,
                  getTouchedSpotIndicator: (LineChartBarData barData, List<int> spotIndexes) {
                    return spotIndexes.map((spotIndex) {
                      return TouchedSpotIndicatorData(
                        FlLine(color: color, strokeWidth: 2),
                        FlDotData(
                          getDotPainter: (spot, percent, barData, index) {
                            return FlDotCirclePainter(
                              radius: 6,
                              color: color,
                              strokeWidth: 2,
                              strokeColor: Colors.white,
                            );
                          },
                        ),
                      );
                    }).toList();
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          physics: AlwaysScrollableScrollPhysics(),
          children: [
            Container(
              height: 180,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.teal, Colors.tealAccent.shade400],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: 16,
                    top: 40,
                    child: IconButton(
                      icon: Icon(widget.darkMode ? Icons.dark_mode : Icons.light_mode, color: Colors.white, size: 28),
                      onPressed: widget.onToggleTheme,
                    ),
                  ),
                  Positioned(
                    left: 24,
                    top: 60,
                    child: Text(
                      'Sensor Dashboard',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 8),
            buildTimeRangeSelector(),
            buildAnimatedCard(child: buildReadingCard("Temperature", latestTemp, Icons.thermostat, Colors.red), index: 0),
            buildAnimatedCard(child: buildReadingCard("Humidity", latestHum, Icons.water_drop, Colors.blue), index: 1),
            buildAnimatedCard(child: buildRelayStatus(), index: 2),
            buildAnimatedCard(child: buildThresholdConfig(), index: 3),
            buildAnimatedCard(child: buildGraph("Temperature (°C)", temps, Colors.red), index: 4),
            buildAnimatedCard(child: buildGraph("Humidity (%)", hums, Colors.blue), index: 5),
            SizedBox(height: 16),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          fetchData();
          fetchThresholds();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Data refreshed!')));
        },
        child: Icon(Icons.refresh),
        backgroundColor: Colors.teal,
      ),
    );
  }
}
