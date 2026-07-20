/// An advertisement resolved from the ads backend for one beacon
/// install point (uuid / major / minor).
class Ad {
  final String id;
  final String title;
  final String content;
  final String linkUrl;

  const Ad({
    required this.id,
    required this.title,
    required this.content,
    required this.linkUrl,
  });

  /// Field names follow the backend response of `GET /api/v1/ads/resolve`.
  factory Ad.fromJson(Map<String, dynamic> json) {
    return Ad(
      id: json['id'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      linkUrl: json['link_url'] as String? ?? '',
    );
  }
}
