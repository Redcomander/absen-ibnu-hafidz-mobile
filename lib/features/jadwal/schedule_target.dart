/// A dashboard selection includes its module because IDs can overlap across modules.
class ScheduleTarget {
  const ScheduleTarget({required this.id, required this.type});
  final int id;
  final String type;

  static ScheduleTarget? fromDashboard(Map<String, dynamic> schedule) {
    final id = int.tryParse('${schedule['id']}');
    if (id == null || id <= 0) return null;
    return ScheduleTarget(
      id: id,
      type: schedule['module'] == 'Diniyyah' ? 'diniyyah' : 'formal',
    );
  }
}

String indonesianMonthYear(DateTime date) {
  const months = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];
  return '${months[date.month - 1]}/${date.year}';
}
