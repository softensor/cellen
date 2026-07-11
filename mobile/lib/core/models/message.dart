class MessageThread {
  final String id;
  final String subject;
  final String threadType;
  final String createdBy;
  final DateTime createdAt;
  final int unreadCount;
  final String? lastMessage;

  const MessageThread({
    required this.id,
    required this.subject,
    required this.threadType,
    required this.createdBy,
    required this.createdAt,
    required this.unreadCount,
    this.lastMessage,
  });

  factory MessageThread.fromJson(Map<String, dynamic> json) {
    return MessageThread(
      id: json['id']?.toString() ?? '',
      subject: json['subject']?.toString() ?? '',
      threadType: json['thread_type']?.toString() ?? json['type']?.toString() ?? 'general',
      createdBy: json['created_by']?.toString() ?? json['created_by_name']?.toString() ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      unreadCount: json['unread_count'] as int? ?? 0,
      lastMessage: json['last_message']?.toString() ?? json['last_message_body']?.toString(),
    );
  }
}

class Message {
  final String id;
  final String senderId;
  final String senderName;
  final String body;
  final DateTime createdAt;

  const Message({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.body,
    required this.createdAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id']?.toString() ?? '',
      senderId: json['sender_id']?.toString() ?? json['sender']?.toString() ?? '',
      senderName: json['sender_name']?.toString() ?? json['sender_username']?.toString() ?? '',
      body: json['body']?.toString() ?? json['content']?.toString() ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
