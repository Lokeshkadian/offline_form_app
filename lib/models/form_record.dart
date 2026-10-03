enum SyncStatus { pending, syncing, synced, failed }

class FormRecord {
  final String localId;
  String? serverId;

  String fullName;
  String mobile;
  String email;
  String category;
  String description;
  DateTime visitDate;

  String? imagePath;
  String? imageUrl;
  bool imageUploaded;

  SyncStatus syncStatus;
  String? syncError;

  DateTime createdAt;
  DateTime updatedAt;

  FormRecord({
    required this.localId,
    this.serverId,
    required this.fullName,
    required this.mobile,
    required this.email,
    required this.category,
    required this.description,
    required this.visitDate,
    this.imagePath,
    this.imageUrl,
    this.imageUploaded = false,
    this.syncStatus = SyncStatus.pending,
    this.syncError,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'local_id': localId,
      'server_id': serverId,
      'full_name': fullName,
      'mobile': mobile,
      'email': email,
      'category': category,
      'description': description,
      'visit_date': visitDate.toIso8601String(),
      'image_path': imagePath,
      'image_url': imageUrl,
      'image_uploaded': imageUploaded ? 1 : 0,
      'sync_status': syncStatus.name,
      'sync_error': syncError,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory FormRecord.fromMap(Map<String, dynamic> map) {
    return FormRecord(
      localId: map['local_id'] as String,
      serverId: map['server_id'] as String?,
      fullName: map['full_name'] as String,
      mobile: map['mobile'] as String,
      email: map['email'] as String,
      category: map['category'] as String,
      description: map['description'] as String,
      visitDate: DateTime.parse(map['visit_date'] as String),
      imagePath: map['image_path'] as String?,
      imageUrl: map['image_url'] as String?,
      imageUploaded: map['image_uploaded'] == 1,
      syncStatus: SyncStatus.values.byName(map['sync_status'] as String),
      syncError: map['sync_error'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
