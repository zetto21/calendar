import 'dart:convert';

import '../logic/date_utils.dart' as date_utils;
import 'secure_http.dart';

class KboTeam {
  final String code, name, color;
  const KboTeam(this.code, this.name, this.color);

  String get displayName => switch (code) {
    'HT' => 'KIA 타이거즈',
    'KT' => 'KT 위즈',
    'LG' => 'LG 트윈스',
    'NC' => 'NC 다이노스',
    'SK' => 'SSG 랜더스',
    'OB' => '두산 베어스',
    'LT' => '롯데 자이언츠',
    'SS' => '삼성 라이온즈',
    'WO' => '키움 히어로즈',
    'HH' => '한화 이글스',
    _ => name,
  };
}

/// KBO teams a user can subscribe to. Naver's team codes on the left.
const kboTeams = [
  KboTeam('HT', 'KIA', '#EA0029'),
  KboTeam('KT', 'KT', '#333333'),
  KboTeam('LG', 'LG', '#C30452'),
  KboTeam('NC', 'NC', '#1D467D'),
  KboTeam('SK', 'SSG', '#CE0E2D'),
  KboTeam('OB', '두산', '#13294B'),
  KboTeam('LT', '롯데', '#002955'),
  KboTeam('SS', '삼성', '#0761A6'),
  KboTeam('WO', '키움', '#7A1E1E'),
  KboTeam('HH', '한화', '#FF6600'),
];

class KboGame {
  final String gameId, date, homeCode, homeName, awayCode, awayName;
  final String? time, stadium;
  final bool cancelled;
  final bool finished;
  final int? homeScore, awayScore;
  const KboGame({
    required this.gameId,
    required this.date,
    this.time,
    required this.homeCode,
    required this.homeName,
    required this.awayCode,
    required this.awayName,
    this.stadium,
    required this.cancelled,
    this.finished = false,
    this.homeScore,
    this.awayScore,
  });
}

/// Fetches KBO schedules directly from Naver Sports' public schedule API
/// (no authentication required).
class KboScheduleService {
  KboScheduleService._();

  static const _base = 'https://api-gw.sports.naver.com/schedule/games';

  /// Fetches every KBO game (all teams) scheduled within [from, to] in a
  /// single request, so callers filtering/merging by team never end up
  /// issuing one request per team and re-fetching the same game twice.
  static Future<List<KboGame>> fetchSchedule(DateTime from, DateTime to) async {
    final uri = Uri.parse(_base).replace(
      queryParameters: {
        'fields': 'basic,schedule,baseball,manualRelayUrl',
        'upperCategoryId': 'kbaseball',
        'categoryId': 'kbo',
        'fromDate': date_utils.toDateKey(from),
        'toDate': date_utils.toDateKey(to),
        'roundCodes': '',
        'size': '500',
      },
    );
    final response = await secureHttpRequest(
      uri,
      headers: {'User-Agent': 'Mozilla/5.0'},
      timeout: const Duration(seconds: 10),
      maxResponseBytes: 4 << 20,
    );
    if (response.statusCode != 200) return const [];
    final body = decodeBoundedJson(
      utf8.decode(response.bodyBytes),
    ) as Map<String, dynamic>;
    final result = body['result'] as Map<String, dynamic>?;
    final games = (result?['games'] as List?) ?? const [];
    if (games.length > 1000) throw const FormatException('경기 일정이 너무 많습니다.');
    return [for (final raw in games) _parseGame(raw as Map<String, dynamic>)];
  }

  static KboGame _parseGame(Map<String, dynamic> raw) {
    final dateTime = DateTime.tryParse(raw['gameDateTime'] as String? ?? '');
    final timeTbd = raw['timeTbd'] == true;
    return KboGame(
      gameId: raw['gameId'] as String,
      date: raw['gameDate'] as String,
      time: dateTime == null || timeTbd
          ? null
          : '${dateTime.hour.toString().padLeft(2, '0')}:'
                '${dateTime.minute.toString().padLeft(2, '0')}',
      homeCode: raw['homeTeamCode'] as String,
      homeName: raw['homeTeamName'] as String,
      awayCode: raw['awayTeamCode'] as String,
      awayName: raw['awayTeamName'] as String,
      stadium: raw['stadium'] as String?,
      cancelled: raw['cancel'] == true,
      finished: raw['statusCode'] == 'RESULT',
      homeScore: raw['homeTeamScore'] as int?,
      awayScore: raw['awayTeamScore'] as int?,
    );
  }
}
