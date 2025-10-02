import 'package:hive/hive.dart';

part 'report.g.dart';

@HiveType(typeId: 0)
class Report extends HiveObject {
  @HiveField(0)
  final String description;

  @HiveField(1)
  final double latitude;

  @HiveField(2)
  final double longitude;

  @HiveField(3)
  final String hazardType;

  @HiveField(4)
  final String userId;

  @HiveField(5)
  final String? mediaUrl;

  @HiveField(6)
  final String status; // Added status with default "unverified"

  Report({
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.hazardType,
    required this.userId,
    this.mediaUrl,
    this.status = 'unverified', // Default status
  });
}
